# -*- coding: utf-8 -*-
"""orca 응답 해석 결정기 — 픽스처는 실측(T-004, T-005)에서 왔다."""
import json
import pathlib
import unittest

import helpers  # noqa: F401
from relaylib import models, orca

FIX = pathlib.Path(__file__).parent / "fixtures" / "orca"


def fx(name):
    p = FIX / name
    return json.loads(p.read_text(encoding="utf-8")) if p.suffix == ".json" else p.read_text(encoding="utf-8")


class Startup(unittest.TestCase):
    def test_ok_with_dispatch(self):
        d = orca.startup(fx("worker-start-ok.json"))
        self.assertEqual(d["action"], "ok")
        self.assertEqual(d["dispatch"], "ctx_b6bfc5cbe8ae")

    def test_input_accepted_without_dispatch_means_lookup(self):
        # --terminal 경로는 보통 dispatch 가 비어 온다 — 추측하지 말고 dispatch-show
        self.assertEqual(orca.startup(fx("worker-start-no-dispatch.json"))["action"], "lookup_dispatch")

    def test_readiness_failure_hides_behind_ok_true(self):
        # 실측(T-005): ok:true 인데 failedStage=agent_readiness, Task 는 이미 failed
        d = orca.startup(fx("worker-start-readiness-failed.json"))
        self.assertEqual(d["action"], "new_task")
        self.assertEqual(d["stage"], "agent_readiness")
        self.assertTrue(d["task_failed"])

    def test_terminal_path_top_level_dispatch_id(self):
        # 실측(Orca 1.4.222, codex --terminal): dispatch 객체 대신 최상위 dispatchId 로 온다
        d = orca.startup(fx("worker-start-terminal-ok.json"))
        self.assertEqual((d["action"], d["dispatch"]), ("ok", "ctx_3f1768a41745"))

    def test_turn_start_unobserved_needs_delivery_check(self):
        # 실측: ok:true·dispatchId 가 있어도 입력이 유실됐다 — ok 로 넘기면 빈 대기 30분을 쓴다
        d = orca.startup(fx("worker-start-turn-unobserved.json"))
        self.assertEqual(d["action"], "confirm_delivery")
        self.assertEqual(d["dispatch"], "ctx_47c1c2d81a60")
        self.assertNotIn("task_failed", d)

    def test_second_startup_failure_calls_human(self):
        d = orca.startup(fx("worker-start-readiness-failed.json"), prior_failures=1)
        self.assertEqual((d["action"], d["reason"]), ("human", "startup_budget"))

    def test_prompt_blocked_is_never_auto_answered(self):
        d = orca.startup(fx("worker-start-prompt-blocked.json"))
        self.assertEqual((d["action"], d["reason"]), ("human", "agent_prompt_blocked"))

    def test_agent_unconfigured_means_tui_idle_not_passed_yet(self):
        d = orca.startup({"ok": False, "error": {"code": "agent_unconfigured", "message": "x"}})
        self.assertEqual(d["action"], "wait_tui_idle")

    def test_task_not_startable_means_new_task(self):
        d = orca.startup({"ok": False, "error": {"code": "task_not_startable", "message": "x"}})
        self.assertEqual(d["action"], "new_task")

    def test_unknown_error_calls_human(self):
        d = orca.startup({"ok": False, "error": {"code": "weird", "message": "x"}})
        self.assertEqual((d["action"], d["reason"]), ("human", "weird"))


class Readiness(unittest.TestCase):
    """tui-idle timeout 이후의 사다리 — 로그인 확인 → 재시도 3회 → 입력창 보이면 1회 재생성 → 사람."""

    SIGNED = "I1002 13:27:02 server_oauth.go:203] OAuth: authenticated successfully as x@example.com\n"

    def test_not_signed_in_calls_human(self):
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log="no auth here", retries=0)
        self.assertEqual((d["action"], d["reason"]), ("human", "not_signed_in"))

    def test_retries_first(self):
        for n in range(3):
            d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=self.SIGNED, retries=n)
            self.assertEqual(d["action"], "retry_tui_idle")
            self.assertEqual(d["wait_seconds"], 30)

    def test_visible_prompt_after_retries_recreates_once(self):
        # 실측(T-004 수정 라운드): 상태줄이 머리글보다 먼저 찍혀 Orca 가 오판, 화면엔 입력창이 있다
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=self.SIGNED, retries=3)
        self.assertEqual(d["action"], "recreate_terminal")

    def test_recreate_only_once(self):
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=self.SIGNED, retries=3, recreated=True)
        self.assertEqual((d["action"], d["reason"]), ("human", "recreate_failed"))

    def test_no_prompt_yet_calls_human(self):
        d = orca.readiness(fx("agy-screen-no-prompt.txt"), agent="antigravity", log=self.SIGNED, retries=3)
        self.assertEqual((d["action"], d["reason"]), ("human", "no_prompt"))

    def test_trust_prompt_calls_human_immediately(self):
        d = orca.readiness(fx("agy-screen-trust.txt"), agent="antigravity", log=self.SIGNED, retries=0)
        self.assertEqual((d["action"], d["reason"]), ("human", "blocked_prompt"))

    def test_not_signed_in_banner_is_not_a_block(self):
        # 시작 직후 한 번 찍히는 문구다 — 'sign in' 차단 문구로 오인하지 않는다
        self.assertIn("not signed in", fx("agy-screen-misordered.txt"))
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=self.SIGNED, retries=0)
        self.assertNotEqual(d.get("reason"), "blocked_prompt")

    def test_stale_block_in_scrollback_is_ignored(self):
        screen = "Do you trust the contents of this project?\n" + "\n" * 30 + fx("agy-screen-misordered.txt")
        d = orca.readiness(screen, agent="antigravity", log=self.SIGNED, retries=3)
        self.assertEqual(d["action"], "recreate_terminal")

    def test_bare_agy_command_recreates_without_retrying(self):
        # 실측(T-007): 단독 agy 로 띄운 터미널은 9회 연속 timeout — 기다리는 건 낭비다
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=self.SIGNED, retries=0, command="agy")
        self.assertEqual((d["action"], d["reason"]), ("recreate_terminal", "bare_launch_command"))
        self.assertEqual(d["launch_command"], orca.AGY_LAUNCH_COMMAND)

    def test_bare_agy_after_recreate_calls_human(self):
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=self.SIGNED, retries=0,
                           command="agy", recreated=True)
        self.assertEqual((d["action"], d["reason"]), ("human", "bare_launch_command"))

    def test_correct_command_keeps_the_ladder(self):
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=self.SIGNED, retries=0,
                           command=orca.AGY_LAUNCH_COMMAND)
        self.assertEqual(d["action"], "retry_tui_idle")

    def test_bare_agy_variants(self):
        for c in ("agy", "agy --model x", "'agy'", r"C:\Users\x\AppData\Local\agy\bin\agy.exe", "AGY"):
            self.assertTrue(orca.is_bare_agy(c), c)
        for c in (orca.AGY_LAUNCH_COMMAND, "codex", "$env:X='1'; agy", None, ""):
            self.assertFalse(orca.is_bare_agy(c), c)

    def test_codex_update_prompt_blocks(self):
        d = orca.readiness(fx("codex-screen-update.txt"), agent="codex", retries=0)
        self.assertEqual((d["action"], d["reason"]), ("human", "blocked_prompt"))

    def test_scrolled_out_header_recreates_without_retrying(self):
        # 실측(T-007 수정 라운드): 긴 세션 뒤 화면은 `>`·Idle 정상인데 머리글이 Orca 꼬리(2000줄) 밖으로 밀려났다
        cmd = orca.AGY_LAUNCH_COMMAND
        d = orca.readiness(fx("agy-screen-long-session.txt"), agent="antigravity", log=self.SIGNED, retries=0, command=cmd)
        self.assertEqual((d["action"], d["reason"]), ("recreate_terminal", "header_scrolled_out"))
        self.assertEqual(d["launch_command"], cmd)
        d = orca.readiness(fx("agy-screen-long-session.txt"), agent="antigravity", log=self.SIGNED, retries=0,
                           command=cmd, recreated=True)
        self.assertEqual((d["action"], d["reason"]), ("human", "header_scrolled_out"))

    def test_header_rule_needs_idle_prompt(self):
        # 일하는 중(Idle 아님)이거나 입력창이 없으면 머리글이 없어도 이 규칙이 아니다
        busy = fx("agy-screen-long-session.txt").replace("│ Idle │", "│ Working │")
        d = orca.readiness(busy, agent="antigravity", log=self.SIGNED, retries=0, command=orca.AGY_LAUNCH_COMMAND)
        self.assertEqual(d["action"], "retry_tui_idle")

    def test_codex_approval_prompt_blocks(self):
        d = orca.readiness(fx("codex-screen-approval.txt"), agent="codex", retries=0)
        self.assertEqual((d["action"], d["reason"]), ("human", "blocked_prompt"))

    def test_codex_needs_no_log(self):
        d = orca.readiness(fx("codex-screen-ready.txt"), agent="codex", retries=3)
        self.assertEqual(d["action"], "recreate_terminal")


class Liveness(unittest.TestCase):
    NOW = 1_800_000_000_000

    def worker(self, **proj):
        w = fx("worker-list-entry.json")
        w["projection"].update(proj)
        return w

    def test_agent_wait_calls_human(self):
        d = orca.liveness(self.worker(), {"agentWait": {"kind": "prompt"}, "lastOutputAt": self.NOW}, "implementer", self.NOW)
        self.assertEqual((d["action"], d["reason"]), ("human", "prompt_wait"))

    def test_next_action_argv_gets_orca_prefix(self):
        w = self.worker(attention={"categories": ["x"], "requiresAction": True})
        d = orca.liveness(w, {"agentWait": None, "lastOutputAt": self.NOW}, "reviewer", self.NOW)
        self.assertEqual(d["action"], "run_argv")
        self.assertEqual(d["argv"], ["orca", "orchestration", "worker-release", "--dispatch", "ctx_3cd95f9cae2c"])

    def test_next_action_ignored_when_not_required(self):
        d = orca.liveness(self.worker(), {"agentWait": None, "lastOutputAt": self.NOW}, "reviewer", self.NOW)
        self.assertEqual(d["action"], "wait")

    def test_stalled_thresholds_by_role(self):
        t = {"agentWait": None, "lastOutputAt": self.NOW - 6 * 60_000}
        self.assertEqual(orca.liveness(self.worker(), t, "implementer", self.NOW)["reason"], "stalled")
        self.assertEqual(orca.liveness(self.worker(), t, "reviewer", self.NOW)["action"], "wait")
        t["lastOutputAt"] = self.NOW - 11 * 60_000
        self.assertEqual(orca.liveness(self.worker(), t, "reviewer", self.NOW)["reason"], "stalled")

    def test_agy_unverifiable_falls_through_to_output_age(self):
        # 실측(T-004): agy 는 unverifiable(missing_status) + nextAction none 만 준다
        w = self.worker(liveness={"verdict": "unverifiable", "reason": "missing_status"},
                        nextAction={"kind": "none"}, attention={"categories": [], "requiresAction": False})
        self.assertEqual(orca.liveness(w, {"agentWait": None, "lastOutputAt": self.NOW - 1000}, "implementer", self.NOW)["action"], "wait")

    def test_approval_screen_calls_human_on_first_empty_wait(self):
        # 실측(T-007): codex 가 승인창에서 멈췄는데 agentWait 은 null — 빈 대기 3회(30분)를 기다리지 않는다
        t = {"agentWait": None, "lastOutputAt": self.NOW}
        d = orca.liveness({}, t, "reviewer", self.NOW, screen=fx("codex-screen-approval.txt"), empty_waits=1)
        self.assertEqual((d["action"], d["reason"]), ("human", "blocked_prompt"))

    def test_layer1_waits_without_projection(self):
        t = {"agentWait": None, "lastOutputAt": self.NOW - 60 * 60_000}
        d = orca.liveness({}, t, "implementer", self.NOW, screen=fx("codex-screen-ready.txt"), empty_waits=2)
        self.assertEqual((d["action"], d["reason"]), ("wait", "layer1"))
        d = orca.liveness(self.worker(), t, "implementer", self.NOW, screen=fx("codex-screen-ready.txt"), empty_waits=3)
        self.assertEqual(d["reason"], "stalled")

    def test_exited_calls_human(self):
        w = self.worker(liveness={"verdict": "exited"}, nextAction={"kind": "none"})
        self.assertEqual(orca.liveness(w, {"agentWait": None, "lastOutputAt": self.NOW}, "implementer", self.NOW)["reason"], "exited")


class ReviewerModel(unittest.TestCase):
    GOOD = 'model = "gpt-6-luna"\ncheck_for_update_on_startup = false\n\n[tui]\nterminal_title = ["app-name", "project-name"]\n'

    def test_model_and_effort_come_from_relay_models(self):
        d = orca.reviewer_model(self.GOOD, {"reviewer": {"model": "gpt-9", "effort": "xhigh"}})
        self.assertEqual(d, {"action": "launch", "agent": "codex", "model": "gpt-9", "effort": "xhigh"})

    def test_effort_defaults_to_high(self):
        d = orca.reviewer_model(self.GOOD, {"reviewer": {"model": "gpt-9"}})
        self.assertEqual(d["effort"], "high")

    def test_codex_config_model_is_ignored(self):
        # config.toml 의 model(평소 용도)을 리뷰어 모델로 쓰지 않는다 — 설정 파일에 model 이 없으면 사람 호출
        for cfg in (None, {}, {"reviewer": {"effort": "medium"}}):
            d = orca.reviewer_model(self.GOOD, cfg)
            self.assertEqual((d["action"], d["reason"]), ("human", "reviewer_model_unset"), cfg)

    def test_same_model_regardless_of_codex_config_model(self):
        cfg = {"reviewer": {"model": "gpt-9"}}
        a = orca.reviewer_model(self.GOOD, cfg)
        b = orca.reviewer_model(self.GOOD.replace('model = "gpt-6-luna"\n', 'model = "other"\n'), cfg)
        c = orca.reviewer_model(self.GOOD.replace('model = "gpt-6-luna"\n', ""), cfg)
        self.assertTrue(a == b == c)

    def test_prereqs_still_required_with_relay_models(self):
        d = orca.reviewer_model('model = "m"\n', {"reviewer": {"model": "gpt-9"}})
        self.assertEqual(d["reason"], "codex_prereq_missing")

    def test_missing_prereqs(self):
        d = orca.reviewer_model('model = "m"\n')
        self.assertEqual(d["action"], "human")
        self.assertEqual(sorted(d["missing"]), ["check_for_update_on_startup = false", "tui.terminal_title 에 app-name"])

    def test_update_check_true_is_missing(self):
        d = orca.reviewer_model(self.GOOD.replace("= false", "= true"))
        self.assertIn("check_for_update_on_startup = false", d["missing"])


AGY_IDS = ("gemini-3.8-flash-high", "gemini-3.8-flash-low", "gemini-3.1-pro-high", "gemini-3.1-pro-low")
AGY_MODELS = "\n".join(["Fetching available models..."] + [i + "\tlabel" for i in AGY_IDS]) + "\n"

class ImplementerModel(unittest.TestCase):
    def test_default_is_bare_launch_command_without_flags(self):
        d = orca.implementer_model()
        self.assertEqual((d["model"], d["launch_command"], d["source"]), (None, orca.AGY_LAUNCH_COMMAND, "agy_default"))

    def test_flags_are_appended_after_null_prefix(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash", "effort": "low"}})
        self.assertEqual(d["launch_command"], "$null=1; agy --model gemini-3.8-flash --effort low")
        self.assertFalse(orca.is_bare_agy(d["launch_command"]))     # Orca 가 에이전트 시작 경로로 가로채지 않는다

    def test_effort_only(self):
        self.assertEqual(orca.agy_launch_command(None, "high"), "$null=1; agy --effort high")

    def test_rejects_shell_metacharacters(self):
        for bad in ("x; rm -rf /", "a b", "$(whoami)", "`id`", "x\ny"):
            with self.assertRaises(models.ModelsError):
                orca.agy_launch_command(bad, None)

    def test_valid_against_agy_models(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash", "effort": "low"}}, AGY_MODELS)
        self.assertEqual(d["action"], "launch")

    def test_level_suffixed_model_with_effort_is_refused_before_launch(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash-low", "effort": "high"}}, AGY_MODELS)
        self.assertEqual((d["action"], d["reason"]), ("human", "agy_model_invalid"))

    def test_unknown_model_and_unsupported_effort(self):
        self.assertEqual(orca.implementer_model({"implementer": {"model": "nope"}}, AGY_MODELS)["reason"], "agy_model_invalid")
        d = orca.implementer_model({"implementer": {"model": "gemini-3.1-pro", "effort": "xhigh"}}, AGY_MODELS)
        self.assertIn("low, high", d["detail"])

    def test_readiness_recreate_uses_configured_command(self):
        cmd = orca.agy_launch_command("gemini-3.8-flash", "low")
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=ReadinessLadder.SIGNED, retries=0,
                           command="agy", launch_command=cmd)
        self.assertEqual(d["launch_command"], cmd)


class CodexLaunchCommand(unittest.TestCase):
    def test_matches_skill_form(self):
        self.assertEqual(orca.codex_launch_command("gpt-9", "high"), "codex --yolo -m gpt-9 -c model_reasoning_effort=high")

    def test_rejects_shell_metacharacters(self):
        with self.assertRaises(models.ModelsError):
            orca.codex_launch_command("x; calc", "high")
        with self.assertRaises(models.ModelsError):
            orca.codex_launch_command("gpt-9", "high; calc")


class SessionModel(unittest.TestCase):
    def test_defaults(self):
        d = orca.session_model("coordinator")
        self.assertEqual((d["action"], d["model"], d["effort"], d["command"]), ("session", None, "medium", "claude --effort medium"))

    def test_configured(self):
        d = orca.session_model("designer", {"designer": {"model": "opus", "effort": "max"}})
        self.assertEqual(d["command"], "claude --model opus --effort max")


AGY_MODELS = "Fetching available models...\ngemini-3.8-flash-high\tG (High)\ngemini-3.8-flash-low\tG (Low)\ngemini-3.1-pro-high\tP\ngemini-3.1-pro-low\tP\n"


class ImplementerModel(unittest.TestCase):
    def test_default_is_bare_launch_command_without_flags(self):
        d = orca.implementer_model()
        self.assertEqual((d["model"], d["launch_command"], d["source"]), (None, orca.AGY_LAUNCH_COMMAND, "agy_default"))

    def test_flags_are_appended_after_null_prefix(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash", "effort": "low"}})
        self.assertEqual(d["launch_command"], "$null=1; agy --model gemini-3.8-flash --effort low")
        self.assertFalse(orca.is_bare_agy(d["launch_command"]))     # Orca 가 에이전트 시작 경로로 가로채지 않는다

    def test_effort_only(self):
        self.assertEqual(orca.agy_launch_command(None, "high"), "$null=1; agy --effort high")

    def test_rejects_shell_metacharacters(self):
        for bad in ("x; rm -rf /", "a b", "$(whoami)", "`id`", "x\ny"):
            with self.assertRaises(models.ModelsError):
                orca.agy_launch_command(bad, None)

    def test_valid_against_agy_models(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash", "effort": "low"}}, AGY_MODELS)
        self.assertEqual(d["action"], "launch")

    def test_level_suffixed_model_with_effort_is_refused_before_launch(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash-low", "effort": "high"}}, AGY_MODELS)
        self.assertEqual((d["action"], d["reason"]), ("human", "agy_model_invalid"))

    def test_unknown_model_and_unsupported_effort(self):
        self.assertEqual(orca.implementer_model({"implementer": {"model": "nope"}}, AGY_MODELS)["reason"], "agy_model_invalid")
        d = orca.implementer_model({"implementer": {"model": "gemini-3.1-pro", "effort": "xhigh"}}, AGY_MODELS)
        self.assertIn("low, high", d["detail"])

    def test_readiness_recreate_uses_configured_command(self):
        cmd = orca.agy_launch_command("gemini-3.8-flash", "low")
        d = orca.readiness(fx("agy-screen-misordered.txt"), agent="antigravity", log=Readiness.SIGNED, retries=0,
                           command="agy", launch_command=cmd)
        self.assertEqual(d["launch_command"], cmd)


class SessionModel(unittest.TestCase):
    def test_defaults(self):
        d = orca.session_model("coordinator")
        self.assertEqual((d["action"], d["model"], d["effort"], d["command"]), ("session", None, "medium", "claude --effort medium"))

    def test_configured(self):
        d = orca.session_model("designer", {"designer": {"model": "opus", "effort": "max"}})
        self.assertEqual(d["command"], "claude --model opus --effort max")


if __name__ == "__main__":
    unittest.main()
