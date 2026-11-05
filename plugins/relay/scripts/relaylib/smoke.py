# -*- coding: utf-8 -*-
"""실제 에이전트 CLI 와 Orca 사이의 경계를 검증한다.

relay 가 워커를 띄우는 경로(`worker-start --agent`)를 smoke 전용 Run 에서 worker_done 까지 잰다 (ADR 0003).
터미널을 먼저 띄우던 리허설 경로는 relay 가 그 기동을 그만두면서 지웠다 (plan 트랙 3).

수동 도구다(CI 아님). CLI 업데이트 뒤, doctor 가 미검증 버전을 알릴 때 돌린다.
통과하면 사람이 references/verified-cli.json 에 버전을 추가한다.

이 모듈은 진단 도구라 orca 를 직접 부른다 — 진행자에게 명령을 조립해 주는 것과는 다르다 (ADR 0001).
"""
import json
import time

PING = "relay-smoke-ping"


def _json(out):
    try:
        return json.loads(out)
    except ValueError:
        return {}


# Task 를 쓰므로 smoke 전용 Run 에 묶고, 정착(worker_done)까지 확인한다.

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
    """worker-start --agent 한 번 → worker_done → ack. run(argv)->(rc, stdout).

    부재(대기 timeout)·질문은 정착이 아니다 — ack 하지 않고 dispatch 를 돌려준다 (Orca 가이드 「Outcome」).
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
    result["state"] = r.get("state")
    dispatch = r.get("dispatchId") or ((r.get("dispatch") or {}).get("id") if isinstance(r.get("dispatch"), dict) else None)
    if not resp.get("ok") or r.get("failedStage") or r.get("state") in ("failed", "outcome_unknown") or not dispatch:
        # 영수증 그대로 보고한다 — 해석(재출발 여부)은 사람이 한다 (ADR 0009)
        result["failed_at"] = "start"
        result["start_error"] = r.get("lastError") or (resp.get("error") or {}).get("code") or r.get("state")
        return result
    result["dispatch"] = dispatch

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
        # 워커는 worker_done 뒤 스스로 닫힌다(Orca 1.4.247 자동 닫힘, ADR 0010) — release 하지 않고 ack 만 한다
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
