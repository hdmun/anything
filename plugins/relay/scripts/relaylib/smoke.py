# -*- coding: utf-8 -*-
"""실제 에이전트 CLI 와 Orca 사이의 경계를 검증한다.

두 경로가 있다.
- terminal(run_agent): 터미널 선기동 리허설. Task 를 쓰지 않아 기동 실패 예산과 무관하다.
- worker-start(run_workers): Orca 기본 기동(`worker-start --agent`)을 smoke 전용 Run 에서 worker_done·release 까지 잰다 (ADR 0003).

수동 도구다(CI 아님). CLI 업데이트 뒤, doctor 가 미검증 버전을 알릴 때 돌린다.
통과하면 사람이 references/verified-cli.json 에 버전을 추가한다.

이 모듈은 진단 도구라 orca 를 직접 부른다 — 진행자에게 명령을 조립해 주는 것과는 다르다 (ADR 0001).
"""
import json
import time

from relaylib import orca

PING = "relay-smoke-ping"
PROMPT = PING + ": reply with the single word OK and do nothing else. Do not use any tools."
DELIVERY_MARK = "HandleUserInput called with text:"


def _json(out):
    try:
        return json.loads(out)
    except ValueError:
        return {}


ATTEMPTS = 3   # 남은 간헐 실패 대비. 2026-10-05 의 '시간대 경합'은 단독 `agy` 실행 경로 탓이었다(orca.AGY_LAUNCH_COMMAND)


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


def _attempt(agent, workdir, run, read_log, sleep, version, command=None,
             idle_timeout_ms=60_000, delivery_timeout_s=60, poll_s=3):
    """agent: antigravity | codex. run(argv)->(rc, stdout). read_log()->agy 최신 로그 내용."""
    command = command or (orca.AGY_LAUNCH_COMMAND if agent == "antigravity" else "codex")   # 설정 파일의 model·effort 를 실은 명령도 리허설한다
    result = {"agent": agent, "version": version, "command": command, "passed": False, "failed_at": None}
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


# --- worker-start 경로: Orca 기본 기동을 끝까지 잰다 (ADR 0003, plan 트랙 0) ----------------------------
# 터미널 경로와 달리 Task 를 쓴다. 그래서 smoke 전용 Run 에 묶고, 정착(worker_done)과 release 까지 확인한다.

WORKER_SPEC = (PING + ": connectivity test only. Do not read, run, or modify anything in the repository. "
               "Immediately send worker_done with --outcome succeeded and the summary "
               "'OK. smoke ping received. No changes made.' using the exact command from your preamble, then stop.")
WORKER_WAIT_MS = 240_000
WAIT_ROUNDS = 3        # 앞선 시도가 남긴 정착 메시지를 넘기며 기다리는 횟수
WAIT_TYPES = "worker_done,escalation,question"


def _payload(msg):
    try:
        return json.loads(msg.get("payload") or "{}")
    except ValueError:
        return {}


def run_worker(agent, workdir, run, version=None, model=None, effort=None,
               wait_ms=WORKER_WAIT_MS, wait_rounds=WAIT_ROUNDS, clock=time.monotonic):
    """worker-start --agent 한 번 → worker_done → release. run(argv)->(rc, stdout).

    부재(대기 timeout)·질문은 release 근거가 아니다 — 워커를 남기고 dispatch 를 돌려준다 (Orca 가이드 「Outcome」).
    """
    result = {"agent": agent, "path": "worker-start", "version": version, "model": model, "effort": effort,
              "passed": False, "failed_at": None}
    argv = ["orca", "orchestration", "worker-start", "--spec", WORKER_SPEC, "--task-title", "relay smoke " + agent,
            "--worktree", "path:" + workdir, "--agent", agent]
    if model:
        argv += ["--model", model]
        if effort:
            argv += ["--effort", effort]
    elif effort:
        result["effort_ignored"] = True      # Orca: --effort 는 --model 이 있어야 한다
    argv.append("--json")

    t0 = clock()
    _, out = run(argv)
    result["start_ms"] = int((clock() - t0) * 1000)
    resp = _json(out)
    r = resp.get("result") or {}
    result["turn_start"] = r.get("turnStart")
    result["mode"] = (r.get("mode") or {}).get("mode")
    result["effective"] = (r.get("launch") or {}).get("effective")
    decision = orca.startup(resp)
    result["startup"] = decision
    if decision["action"] != "ok":
        result["failed_at"] = "start"
        return result
    dispatch = result["dispatch"] = decision["dispatch"]

    stray = []
    for _ in range(wait_rounds):
        _, out = run(["orca", "orchestration", "check", "--wait", "--types", WAIT_TYPES,
                      "--timeout-ms", str(wait_ms), "--json"])
        res = _json(out).get("result") or {}
        msgs = res.get("messages") or []
        mine = [m for m in msgs if _payload(m).get("dispatchId") == dispatch]
        if not mine:
            if not msgs:
                break                        # 빈 대기 — 더 기다리지 않고 보고한다
            stray += [_payload(m).get("dispatchId") for m in msgs]
            run(["orca", "orchestration", "check", "--ack", res.get("deliveryId"), "--json"])
            continue
        msg = mine[0]
        result["done_ms"] = int((clock() - t0) * 1000)
        if stray:
            result["stray"] = stray
        if msg.get("type") != "worker_done":
            result["failed_at"] = msg.get("type")      # 질문·에스컬레이션은 사람이 본다 — ack 하지 않는다
            return result
        _, out = run(["orca", "orchestration", "worker-release", "--dispatch", dispatch, "--json"])
        result["release"] = (_json(out).get("result") or {}).get("processAction")
        run(["orca", "orchestration", "check", "--ack", res.get("deliveryId"), "--json"])
        if _payload(msg).get("outcome") == "succeeded":
            result["passed"] = True
        else:
            result["failed_at"] = "outcome"
        return result
    if stray:
        result["stray"] = stray
    result["failed_at"] = "worker_done"
    return result


def run_workers(agent, workdir, run, repeat=1, run_id=None, objective=None, **kw):
    """smoke 전용 Run 에 묶고 repeat 번 잰다. 전부 통과해야 통과. 첫 실패에서 멈춘다(남은 워커가 증거다).

    이 프로세스를 띄운 터미널의 Run 바인딩이 바뀐다 — 진행 중인 Run 이 있었으면 끝난 뒤 run-use 로 돌아간다.
    """
    if run_id:
        _, out = run(["orca", "orchestration", "run-use", "--id", run_id, "--json"])
    else:
        _, out = run(["orca", "orchestration", "run-create", "--objective",
                      objective or "relay smoke: worker-start --agent " + agent, "--json"])
    bound = ((_json(out).get("result") or {}).get("run") or {}).get("id") or run_id
    tries = []
    for _ in range(repeat):
        r = run_worker(agent, workdir, run, **kw)
        tries.append(r["failed_at"] or "passed")
        if not r["passed"]:
            break
    r["run"] = bound
    r["attempts"] = tries
    r["passed"] = len(tries) == repeat and all(t == "passed" for t in tries)
    return r
