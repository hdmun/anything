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
        self.assertEqual(d["action"], "retry")     # 같은 Task 에 --retry-of 로 재출발 (Orca 가이드 recovery)
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

    def test_agent_path_ok_reports_effective_model(self):
        # 실측(트랙 0, Orca 1.4.245): --agent 경로는 dispatchId·turnStart observed·launch.effective 를 준다
        d = orca.startup(fx("worker-start-agent-codex.json"))
        self.assertEqual((d["action"], d["dispatch"], d["model"]), ("ok", "ctx_17b7f5d4033a", "gpt-6.1-sol"))
        d = orca.startup(fx("worker-start-agent-agy.json"))
        self.assertEqual((d["action"], d["model"]), ("ok", None))     # agy 기본 모델이면 effective.model 이 null

    def test_agent_unconfigured_calls_human(self):
        # --agent 경로는 Orca 가 터미널을 만들고 태깅한다 — 터미널을 먼저 띄우던 시절의 tui-idle 대기는 없다
        d = orca.startup({"ok": False, "error": {"code": "agent_unconfigured", "message": "x"}})
        self.assertEqual((d["action"], d["reason"]), ("human", "agent_unconfigured"))

    def test_task_not_startable_means_retry_of(self):
        # 실패한 Task 에 --retry-of 없이 worker-start 를 걸면 거부된다 — 재출발은 --retry-of 로
        d = orca.startup({"ok": False, "error": {"code": "task_not_startable", "message": "x"}})
        self.assertEqual(d["action"], "retry")

    def test_unknown_error_calls_human(self):
        d = orca.startup({"ok": False, "error": {"code": "weird", "message": "x"}})
        self.assertEqual((d["action"], d["reason"]), ("human", "weird"))


class Liveness(unittest.TestCase):
    """빈 대기 뒤 판정. 입력은 orchestration 동사뿐이다 — worker-list(projection)·worker-show·worker-read (ADR 0003)."""

    NOW = 1_800_000_000_000

    def worker(self, **proj):
        w = fx("worker-list-entry.json")
        w["projection"].update(proj)
        return w

    def show(self, agent_wait=None, last=None):
        # worker-show: observation.agentWait 는 양성 신호만, terminal.lastOutputAt 은 3층 벽시계
        return {"observation": {"status": "live", "agentWait": agent_wait}, "terminal": {"lastOutputAt": self.NOW if last is None else last}}

    @staticmethod
    def read_terminal(text):
        # worker-read 가 터미널로 떨어진 경우(agy: provider_unsupported) — 화면 꼬리가 있다
        return {"source": "terminal", "terminal": {"tail": text.splitlines()}}

    def test_real_worker_show_and_read_shapes(self):
        # 실측(트랙 0, agy 하위 워커): worker-read 는 terminal.tail, worker-show 는 terminal.lastOutputAt
        show, read = fx("worker-show-agy.json")["result"], fx("worker-read-terminal-agy.json")["result"]
        self.assertEqual(read["source"], "terminal")
        d = orca.liveness(self.worker(), show, "implementer", show["terminal"]["lastOutputAt"] + 1000, read=read, empty_waits=3)
        self.assertEqual(d["action"], "wait")       # 'not signed in' 배너는 차단이 아니다

    def test_agent_wait_calls_human(self):
        d = orca.liveness(self.worker(), self.show(agent_wait={"kind": "prompt", "evidence": "hook"}), "implementer", self.NOW)
        self.assertEqual((d["action"], d["reason"]), ("human", "prompt_wait"))

    def test_next_action_argv_gets_orca_prefix(self):
        w = self.worker(attention={"categories": ["x"], "requiresAction": True})
        d = orca.liveness(w, self.show(), "reviewer", self.NOW)
        self.assertEqual(d["action"], "run_argv")
        self.assertEqual(d["argv"], ["orca", "orchestration", "worker-release", "--dispatch", "ctx_3cd95f9cae2c"])

    def test_next_action_ignored_when_not_required(self):
        d = orca.liveness(self.worker(), self.show(), "reviewer", self.NOW)
        self.assertEqual(d["action"], "wait")

    def test_stalled_thresholds_by_role(self):
        s = self.show(last=self.NOW - 6 * 60_000)
        self.assertEqual(orca.liveness(self.worker(), s, "implementer", self.NOW)["reason"], "stalled")
        self.assertEqual(orca.liveness(self.worker(), s, "reviewer", self.NOW)["action"], "wait")
        s = self.show(last=self.NOW - 11 * 60_000)
        self.assertEqual(orca.liveness(self.worker(), s, "reviewer", self.NOW)["reason"], "stalled")

    def test_agy_unverifiable_falls_through_to_output_age(self):
        # 실측(T-004): agy 는 unverifiable(missing_status) + nextAction none 만 준다
        w = self.worker(liveness={"verdict": "unverifiable", "reason": "missing_status"},
                        nextAction={"kind": "none"}, attention={"categories": [], "requiresAction": False})
        self.assertEqual(orca.liveness(w, self.show(last=self.NOW - 1000), "implementer", self.NOW)["action"], "wait")

    def test_prompt_in_worker_read_tail_calls_human_on_first_empty_wait(self):
        # 실측(T-007): codex 가 승인창에서 멈췄는데 agentWait 은 null — 빈 대기 3회(30분)를 기다리지 않는다
        d = orca.liveness({}, self.show(), "reviewer", self.NOW, read=self.read_terminal(fx("codex-screen-approval.txt")), empty_waits=1)
        self.assertEqual((d["action"], d["reason"]), ("human", "blocked_prompt"))

    def test_transcript_read_has_no_screen_to_check(self):
        # transcript 로 읽히는 워커(codex·claude)는 화면이 없다 — 확인창은 observation.agentWait 로만 잡는다
        read = {"source": "transcript", "transcript": {"messages": [{"role": "assistant", "blocks": [{"type": "text", "text": "Allow once?"}]}]}}
        d = orca.liveness({}, self.show(), "reviewer", self.NOW, read=read, empty_waits=1)
        self.assertEqual((d["action"], d["reason"]), ("wait", "layer1"))

    def test_layer1_waits_without_projection(self):
        s = self.show(last=self.NOW - 60 * 60_000)
        read = self.read_terminal(fx("codex-screen-ready.txt"))
        d = orca.liveness({}, s, "implementer", self.NOW, read=read, empty_waits=2)
        self.assertEqual((d["action"], d["reason"]), ("wait", "layer1"))
        d = orca.liveness(self.worker(), s, "implementer", self.NOW, read=read, empty_waits=3)
        self.assertEqual(d["reason"], "stalled")

    def test_worker_without_terminal_waits(self):
        # 채팅으로 뜬 워커는 worker-show 에 terminal 이 없을 수 있다 — 벽시계가 없으면 기다린다
        d = orca.liveness(self.worker(), {"observation": {"status": "live"}, "terminal": None}, "implementer", self.NOW)
        self.assertEqual((d["action"], d["reason"]), ("wait", "no_output_timestamp"))

    def test_exited_calls_human(self):
        w = self.worker(liveness={"verdict": "exited"}, nextAction={"kind": "none"})
        self.assertEqual(orca.liveness(w, self.show(), "implementer", self.NOW)["reason"], "exited")


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
    """구현 워커(agy)는 worker-start --agent antigravity 로 띄운다 — 결정기는 그 인자만 돌려준다 (ADR 0003)."""

    def test_default_launches_agy_without_model_flags(self):
        d = orca.implementer_model()
        self.assertEqual(d, {"action": "launch", "agent": "antigravity", "model": None, "effort": None, "source": "agy_default"})

    def test_configured_model_and_effort(self):
        d = orca.implementer_model({"implementer": {"model": "gemini-3.8-flash", "effort": "low"}})
        self.assertEqual((d["action"], d["model"], d["effort"], d["source"]), ("launch", "gemini-3.8-flash", "low", "relay_models"))

    def test_effort_without_model_is_refused_before_launch(self):
        # Orca: worker-start 의 --effort 는 --model 이 있어야 한다. 조용히 버리지 않는다
        d = orca.implementer_model({"implementer": {"effort": "high"}})
        self.assertEqual((d["action"], d["reason"]), ("human", "effort_needs_model"))

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


class DesignerModel(unittest.TestCase):
    """설계 세션은 사람이 연 세션이라 플러그인이 모델을 바꿀 수 없다 — 따를 명령만 안내한다."""

    def test_defaults(self):
        d = orca.session_model("designer")
        self.assertEqual((d["action"], d["model"], d["effort"], d["command"]), ("session", None, "high", "claude --effort high"))

    def test_configured(self):
        d = orca.session_model("designer", {"designer": {"model": "opus", "effort": "max"}})
        self.assertEqual(d["command"], "claude --model opus --effort max")


class CoordinatorModel(unittest.TestCase):
    """진행자는 설계 세션이 worker-start --agent claude 로 띄우는 워커다 (ADR 0004) — 기동 인자를 돌려준다."""

    def test_default_launches_opus_low_worker(self):
        d = orca.coordinator_model()
        self.assertEqual((d["action"], d["agent"], d["model"], d["effort"], d["source"]),
                         ("launch", "claude", "opus", "low", "default"))
        self.assertNotIn("command", d)      # 사람에게 안내할 claude 명령줄은 이제 없다

    def test_configured_values_win(self):
        d = orca.coordinator_model({"coordinator": {"model": "opus", "effort": "high"}})
        self.assertEqual((d["model"], d["effort"], d["source"]), ("opus", "high", "relay_models"))



if __name__ == "__main__":
    unittest.main()
