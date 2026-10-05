# -*- coding: utf-8 -*-
"""실제 에이전트 CLI 와 Orca 사이의 경계를 Task 없이 검증한다 — 기동 실패 예산을 쓰지 않는 리허설.

수동 도구다(CI 아님). CLI 업데이트 뒤, doctor 가 미검증 버전을 알릴 때 돌린다.
통과하면 사람이 references/verified-cli.json 에 버전을 추가한다.

이 모듈은 진단 도구라 orca 를 직접 부른다 — 진행자에게 명령을 조립해 주는 것과는 다르다 (ADR 0001).
"""
import json
import time

PING = "relay-smoke-ping"
PROMPT = PING + ": reply with the single word OK and do nothing else. Do not use any tools."
DELIVERY_MARK = "HandleUserInput called with text:"


def _json(out):
    try:
        return json.loads(out)
    except ValueError:
        return {}


ATTEMPTS = 3   # 준비 감지 경합은 시간대에 몰려 간헐적이다(2026-10-05: 연속 8회 실패 뒤 13회 중 12회 통과)


def run_agent(agent, workdir, run, read_log, sleep=time.sleep, version=None, attempts=ATTEMPTS, **kw):
    """터미널을 새로 만들며 최대 attempts 번 시도한다. 한 번이라도 통과하면 통과 — 실패 이력은 남긴다."""
    tries = []
    for _ in range(attempts):
        r = _attempt(agent, workdir, run, read_log, sleep=sleep, version=version, **kw)
        tries.append(r["failed_at"] or "passed")
        if r["passed"]:
            break
    r["attempts"] = tries
    return r


def _attempt(agent, workdir, run, read_log, sleep, version,
             idle_timeout_ms=60_000, delivery_timeout_s=60, poll_s=3):
    """agent: antigravity | codex. run(argv)->(rc, stdout). read_log()->agy 최신 로그 내용."""
    command = "agy" if agent == "antigravity" else "codex"
    result = {"agent": agent, "version": version, "passed": False, "failed_at": None}
    rc, out = run(["orca", "terminal", "create", "--worktree", "path:" + workdir,
                   "--title", "relay-smoke " + agent, "--command", command, "--json"])
    handle = ((_json(out).get("result") or {}).get("terminal") or {}).get("handle")
    if rc != 0 or not handle:
        result["failed_at"] = "create"
        return result
    try:
        t0 = time.monotonic()
        rc, out = run(["orca", "terminal", "wait", "--terminal", handle, "--for", "tui-idle",
                       "--timeout-ms", str(idle_timeout_ms), "--json"])
        result["tui_idle_ms"] = int((time.monotonic() - t0) * 1000)
        if rc != 0 or not _json(out).get("ok"):
            result["failed_at"] = "tui_idle"
            return result
        run(["orca", "terminal", "send", "--terminal", handle, "--text", PROMPT, "--enter", "--json"])
        waited = 0
        while waited <= delivery_timeout_s:
            if agent == "antigravity":
                delivered = DELIVERY_MARK in (read_log() or "")
            else:
                _, out = run(["orca", "terminal", "read", "--terminal", handle, "--screen", "--json"])
                tail = ((_json(out).get("result") or {}).get("terminal") or {}).get("tail") or []
                delivered = any(PING in line for line in tail)
            if delivered:
                result["passed"] = True
                return result
            sleep(poll_s)
            waited += poll_s
        result["failed_at"] = "delivery"
        return result
    finally:
        run(["orca", "terminal", "close", "--terminal", handle, "--json"])
