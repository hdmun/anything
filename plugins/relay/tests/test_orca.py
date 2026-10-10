# -*- coding: utf-8 -*-
"""orca 응답 해석 결정기 — 픽스처는 실측(T-004, T-005)에서 왔다."""
import json
import pathlib
import unittest

import helpers  # noqa: F401
from relaylib import orca

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

    def test_exited_calls_human(self):
        w = self.worker(liveness={"verdict": "exited"}, nextAction={"kind": "none"})
        self.assertEqual(orca.liveness(w, {"agentWait": None, "lastOutputAt": self.NOW}, "implementer", self.NOW)["reason"], "exited")


class ReviewerModel(unittest.TestCase):
    GOOD = 'model = "gpt-6-luna"\ncheck_for_update_on_startup = false\n\n[tui]\nterminal_title = ["app-name", "project-name"]\n'

    def test_follows_codex_default_model(self):
        d = orca.reviewer_model(self.GOOD)
        self.assertEqual(d, {"action": "launch", "agent": "codex", "model": "gpt-6-luna", "effort": "high"})

    def test_missing_prereqs(self):
        d = orca.reviewer_model('model = "m"\n')
        self.assertEqual(d["action"], "human")
        self.assertEqual(sorted(d["missing"]), ["check_for_update_on_startup = false", "tui.terminal_title 에 app-name"])

    def test_update_check_true_is_missing(self):
        d = orca.reviewer_model(self.GOOD.replace("= false", "= true"))
        self.assertIn("check_for_update_on_startup = false", d["missing"])

    def test_no_model_calls_human(self):
        d = orca.reviewer_model(self.GOOD.replace('model = "gpt-6-luna"\n', ""))
        self.assertEqual((d["action"], d["reason"]), ("human", "codex_model_unset"))


if __name__ == "__main__":
    unittest.main()
