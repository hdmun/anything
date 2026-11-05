# -*- coding: utf-8 -*-
"""smoke 의 worker-start 경로 — Orca 기본 기동(`worker-start --agent`)을 끝까지(worker_done) 잰다 (plan 트랙 0).

픽스처는 2026-11-02 Orca 1.4.245 실측 응답이다 (agy 1.4.12, codex 0.159.3).
"""
import json
import unittest

from helpers import PLUGIN_ROOT
from relaylib import smoke

FIX = PLUGIN_ROOT / "tests" / "fixtures" / "orca"


def fixture(name):
    return json.loads((FIX / name).read_text(encoding="utf-8"))


def done_message(dispatch, outcome="succeeded", type_="worker_done", delivery="delivery_1"):
    """check --wait 응답. 실측 형식(check-worker-done-agy.json)에서 dispatch·outcome·type 만 바꾼다."""
    resp = fixture("check-worker-done-agy.json")
    resp["result"]["deliveryId"] = delivery
    msg = resp["result"]["messages"][0]
    msg["type"] = type_
    payload = json.loads(msg["payload"])
    payload.update(dispatchId=dispatch, outcome=outcome)
    msg["payload"] = json.dumps(payload)
    return resp


def done_message_1_4_247(dispatch, outcome="succeeded"):
    """1.4.247+ check 응답: payload 가 객체이고 deliveryId 가 없다(소비하는 check 가 스스로 처리 완료로 표시한다)."""
    resp = fixture("1.4.247/agy-check-worker-done.json")
    resp["result"]["messages"][0]["payload"].update(dispatchId=dispatch, outcome=outcome)
    return resp


EMPTY_WAIT = {"ok": True, "result": {"messages": [], "count": 0, "timedOut": True}}


class FakeOrca(object):
    """worker-start 경로용 가짜. checks: check --wait 가 차례로 돌려줄 응답 목록."""

    def __init__(self, start, checks=(), run_id="run_smoke"):
        self.start, self.checks, self.run_id, self.calls = start, list(checks), run_id, []

    def run(self, argv):
        self.calls.append(argv)
        sub = argv[1:3]
        if sub == ["orchestration", "run-create"] or sub == ["orchestration", "run-use"]:
            return 0, json.dumps({"ok": True, "result": {"run": {"id": self.run_id}}})
        if sub == ["orchestration", "worker-start"]:
            return 0, json.dumps(self.start)
        if sub == ["orchestration", "check"] and "--wait" in argv:
            return 0, json.dumps(self.checks.pop(0) if self.checks else EMPTY_WAIT)
        if sub == ["orchestration", "worker-release"]:
            return 0, json.dumps(fixture("worker-release-closed.json"))
        return 0, '{"ok": true, "result": {"count": 0}}'

    def made(self, verb):
        return [c for c in self.calls if c[1:3] == ["orchestration", verb]]

    def acks(self):
        return [c for c in self.made("check") if "--ack" in c]


CODEX = fixture("worker-start-agent-codex.json")
AGY = fixture("worker-start-agent-agy.json")
CODEX_DISPATCH = CODEX["result"]["dispatchId"]
AGY_DISPATCH = AGY["result"]["dispatchId"]


class WorkerPath(unittest.TestCase):
    def test_codex_pass_records_launch_then_acks_without_release(self):
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH)])
        r = smoke.run_worker("codex", "C:/w", o.run, model="gpt-6.1-sol", effort="high", version="0.159.3")
        self.assertTrue(r["passed"], r)
        self.assertEqual(r["path"], "worker-start")
        self.assertEqual(r["turn_start"], "observed")
        self.assertEqual(r["mode"], "terminal")
        self.assertEqual(r["effective"], {"agent": "codex", "model": "gpt-6.1-sol", "effort": "high"})
        self.assertNotIn("release", r)
        verbs = [c[2] for c in o.calls]
        # 워커는 worker_done 뒤 스스로 닫힌다 — release 없이 ack 만 한다 (ADR 0010)
        self.assertEqual(verbs, ["worker-start", "check", "check"])
        self.assertIn("--ack", o.calls[-1])

    def test_agy_default_model_passes_without_model_flags(self):
        o = FakeOrca(AGY, [done_message(AGY_DISPATCH)])
        r = smoke.run_worker("antigravity", "C:/w", o.run, version="1.4.12")
        self.assertTrue(r["passed"], r)
        start = o.made("worker-start")[0]
        self.assertNotIn("--model", start)
        self.assertNotIn("--effort", start)
        self.assertEqual(start[start.index("--agent") + 1], "antigravity")
        self.assertEqual(start[start.index("--worktree") + 1], "path:C:/w")

    def test_effort_without_model_is_not_passed(self):
        # Orca: --effort 는 --model 이 있어야 한다. 설정에 effort 만 있으면 넘기지 않고 기록만 남긴다
        o = FakeOrca(AGY, [done_message(AGY_DISPATCH)])
        r = smoke.run_worker("antigravity", "C:/w", o.run, effort="low", version="1.4.12")
        self.assertNotIn("--effort", o.made("worker-start")[0])
        self.assertTrue(r["effort_ignored"])

    def test_model_and_effort_are_passed_together(self):
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH)])
        smoke.run_worker("codex", "C:/w", o.run, model="m1", effort="high", version="1")
        start = o.made("worker-start")[0]
        self.assertEqual(start[start.index("--model") + 1], "m1")
        self.assertEqual(start[start.index("--effort") + 1], "high")

    def test_start_failure_does_not_wait_or_release(self):
        o = FakeOrca(fixture("worker-start-readiness-failed.json"))
        r = smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertEqual((r["passed"], r["failed_at"]), (False, "start"))
        self.assertEqual(r["start_error"], "timeout")
        self.assertEqual(o.made("check"), [])
        self.assertEqual(o.made("worker-release"), [])

    def test_no_worker_done_is_not_released(self):
        # 부재는 정착이 아니다 — 워커를 남기고 dispatch 를 보고한다
        o = FakeOrca(CODEX, [EMPTY_WAIT])
        r = smoke.run_worker("codex", "C:/w", o.run, version="1", wait_rounds=1)
        self.assertEqual((r["passed"], r["failed_at"]), (False, "worker_done"))
        self.assertEqual(r["dispatch"], CODEX_DISPATCH)
        self.assertEqual(o.made("worker-release"), [])

    def test_question_from_worker_is_left_for_a_human(self):
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH, type_="question")])
        r = smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertEqual((r["passed"], r["failed_at"]), (False, "question"))
        self.assertEqual(o.made("worker-release"), [])
        self.assertEqual(o.acks(), [], "답하지 않은 질문은 ack 하지 않는다")

    def test_failed_outcome_is_acked_but_not_passed(self):
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH, outcome="failed")])
        r = smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertEqual((r["passed"], r["failed_at"]), (False, "outcome"))
        self.assertEqual(o.made("worker-release"), [])
        self.assertEqual(len(o.acks()), 1)

    def test_stray_settlement_is_acked_and_waiting_continues(self):
        # 앞선 smoke 시도가 남긴 정착 메시지 — 이 smoke Run 의 것이므로 ack 하고 계속 기다린다
        stray = done_message("ctx_old", delivery="delivery_old")
        o = FakeOrca(CODEX, [stray, done_message(CODEX_DISPATCH)])
        r = smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertTrue(r["passed"], r)
        self.assertEqual(r["stray"], ["ctx_old"])
        self.assertEqual(len(o.acks()), 2)

    def test_asks_for_the_full_receipt(self):
        # Orca 1.4.247 부터 기본은 간결 보기라 launch·turnStart 가 없다 — 전체 기록을 받는다
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH)])
        smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertIn("--full", o.made("worker-start")[0])

    def test_full_receipt_from_1_4_247_records_launch(self):
        start = fixture("1.4.247/codex-worker-start-yolo.json")
        o = FakeOrca(start, [done_message(start["result"]["dispatchId"])])
        r = smoke.run_worker("codex", "C:/w", o.run, version="0.159.3")
        self.assertTrue(r["passed"], r)
        self.assertEqual((r["mode"], r["turn_start"]), ("terminal", "observed"))
        self.assertEqual(r["effective"], {"agent": "codex", "model": None, "effort": None})

    def test_concise_receipt_does_not_crash(self):
        # 간결 보기의 mode 는 문자열이다 (Orca 1.4.248 smoke 에서 AttributeError 로 죽었다)
        start = fixture("1.4.247/agy-worker-start.json")
        o = FakeOrca(start, [done_message(start["result"]["dispatchId"])])
        r = smoke.run_worker("antigravity", "C:/w", o.run, version="1.5.0")
        self.assertTrue(r["passed"], r)
        self.assertEqual(r["mode"], "terminal")
        self.assertIsNone(r["effective"])

    def test_object_payload_without_delivery_passes_without_ack(self):
        # Orca 1.4.248 smoke 에서 json.loads(dict) 로 죽었다. deliveryId 가 없으면 ack 할 것도 없다
        o = FakeOrca(CODEX, [done_message_1_4_247(CODEX_DISPATCH)])
        r = smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertTrue(r["passed"], r)
        self.assertEqual(o.acks(), [])

    def test_object_payload_stray_is_skipped_without_ack(self):
        o = FakeOrca(CODEX, [done_message_1_4_247("ctx_old"), done_message_1_4_247(CODEX_DISPATCH)])
        r = smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertTrue(r["passed"], r)
        self.assertEqual(r["stray"], ["ctx_old"])
        self.assertEqual(o.acks(), [])

    def test_commands_start_with_orca(self):
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH)])
        smoke.run_worker("codex", "C:/w", o.run, version="1")
        self.assertTrue(all(c[0] == "orca" for c in o.calls))


class Repeat(unittest.TestCase):
    def test_binds_a_fresh_run_and_repeats(self):
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH) for _ in range(3)])
        r = smoke.run_workers("codex", "C:/w", o.run, repeat=3, version="1")
        self.assertTrue(r["passed"], r)
        self.assertEqual(r["run"], "run_smoke")
        self.assertEqual(r["attempts"], ["passed"] * 3)
        self.assertEqual(len(o.made("run-create")), 1)
        self.assertEqual(len(o.made("worker-start")), 3)

    def test_reuses_a_given_run(self):
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH)])
        smoke.run_workers("codex", "C:/w", o.run, repeat=1, run_id="run_given", version="1")
        self.assertEqual(o.made("run-create"), [])
        use = o.made("run-use")[0]
        self.assertEqual(use[use.index("--id") + 1], "run_given")

    def test_stops_at_the_first_failure(self):
        # 실패한 시도는 워커를 남길 수 있다 — 증거를 지키려고 더 띄우지 않는다
        o = FakeOrca(CODEX, [done_message(CODEX_DISPATCH), EMPTY_WAIT])
        r = smoke.run_workers("codex", "C:/w", o.run, repeat=3, version="1", wait_rounds=1)
        self.assertFalse(r["passed"])
        self.assertEqual(r["attempts"], ["passed", "worker_done"])
        self.assertEqual(len(o.made("worker-start")), 2)


class Cli(unittest.TestCase):
    """옵션 오용은 orca 를 부르기 전에 입력 오류(2)로 막는다."""

    def cli(self, *args):
        import subprocess
        import sys
        from helpers import SCRIPTS
        return subprocess.run([sys.executable, str(SCRIPTS / "relay_cli.py"), "smoke", "--dir", "C:/nowhere", *args],
                              capture_output=True)

    def test_model_needs_a_single_agent(self):
        self.assertEqual(self.cli("--model", "m").returncode, 2)


if __name__ == "__main__":
    unittest.main()
