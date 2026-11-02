# -*- coding: utf-8 -*-
"""orca 응답·화면 해석 결정기 — SKILL (d)(e) 의 정본.

결정만 돌려준다. orca 명령 조립은 에이전트가 Orca 가이드를 읽고 한다 (ADR 0001·0003).
워커는 worker-start --agent 로 띄운다 — 결정기는 그 인자(agent·model·effort)를 돌려줄 뿐 명령줄을 만들지 않는다.
모든 근거는 실측(poker-server T-004~T-007, plan 트랙 0)이다 — 테스트 픽스처에 남아 있다.
"""
import re

from relaylib import models

try:
    import tomllib
except ImportError:  # pragma: no cover — Python < 3.11
    tomllib = None

STARTUP_BUDGET = 2            # 같은 Task 계열의 기동 실패 허용 횟수 (Orca 는 3회째에 circuit-break)
STALL_MS = {"implementer": 5 * 60_000, "reviewer": 10 * 60_000}
SCREEN_TAIL_LINES = 15        # 답한 프롬프트가 스크롤백에 남아도 오판하지 않게 화면 맨 아래만 본다
LAYER1_EMPTY_WAITS = 3        # 이 횟수 전에는 화면 확인만 하고 그냥 기다린다 (SKILL (e) 1층)

# Orca 의 TERMINAL_WAIT_BLOCKED_SENTINEL_RE 와 같은 계열 + agy 로그인 요구.
# 'sign in' 은 단어 경계로만 — 시작 직후 찍히는 'not signed in' 배너는 차단이 아니다.
BLOCKED_RE = re.compile(
    r"update available|choose working directory to|codex just got an upgrade|hooks need review|do you trust"
    r"|trust this|trusted workspace|press enter to (?:confirm|continue|view|insert)|press t to trust"
    r"|permission required|requires permission|allow once|allow always|run this command\?|\bsign in\b"
    # codex 명령 승인창 (실측 T-007: git status --short, Get-Location 에서 멈춤)
    r"|would you like to run the following command|yes, proceed|don'?t ask again",
    re.I,
)


def _d(action, **kw):
    return dict(action=action, **kw)


def startup(resp, prior_failures=0):
    """worker-start 응답 → 다음 행동. ok 는 믿지 않는다 — 준비 감지 실패도 ok:true 로 온다(T-005)."""
    if not resp.get("ok"):
        code = (resp.get("error") or {}).get("code", "unknown")
        if code == "task_not_startable":
            return _d("retry", reason=code, task_failed=True)
        return _d("human", reason=code)

    r = resp.get("result") or {}
    failed = r.get("failedStage")
    if failed:
        err = r.get("lastError")
        if err == "agent_prompt_blocked":
            return _d("human", reason="agent_prompt_blocked", stage=failed)   # 프롬프트 자동 응답 금지
        if prior_failures + 1 >= STARTUP_BUDGET:
            return _d("human", reason="startup_budget", stage=failed, error=err, task_failed=True)
        # agent_readiness 한 번으로 Task 는 failed 다 — 재출발은 같은 Task 에 --retry-of (Orca 가이드 recovery)
        return _d("retry", stage=failed, error=err, task_failed=True)

    dispatch = r.get("dispatch") or {}
    did = (dispatch.get("id") if isinstance(dispatch, dict) else None) or r.get("dispatchId")   # 1.4.222 는 최상위 dispatchId
    model = ((r.get("launch") or {}).get("effective") or {}).get("model")
    if r.get("state") == "outcome_unknown" or r.get("turnStart") == "unobserved":
        # 실측(2026-10-11, codex --terminal 5회 중 1회): 입력을 썼다는데 입력창은 비어 있고 Dispatch 는 pending 에 머물렀다.
        # Orca 말대로 늦게 시작할 수도 있으니 실패로 단정하지 않고 전달부터 확인한다
        return _d("confirm_delivery", dispatch=did, model=model, reason=r.get("stage") or "turn_start_unobserved")
    if did:
        return _d("ok", dispatch=did, model=model)
    return _d("lookup_dispatch", model=model)


def _tail(screen):
    lines = [l.rstrip() for l in screen.splitlines()]
    while lines and not lines[-1].strip():
        lines.pop()
    return lines[-SCREEN_TAIL_LINES:]


def _read_tail(read):
    """worker-read 결과 → 화면 꼬리 줄 목록. 터미널로 읽힌 경우만 화면이 있다 — transcript 는 None."""
    if not read or read.get("source") != "terminal":
        return None
    return (read.get("terminal") or {}).get("tail") or []


def liveness(worker, show, role, now_ms, read=None, empty_waits=None):
    """빈 대기 뒤의 판정 (SKILL (e)). 입력은 orchestration 동사의 결과뿐이다 (ADR 0003):
    worker 는 worker-list 항목(projection), show 는 worker-show 결과, read 는 worker-read 결과.

    empty_waits(연속 빈 대기 횟수)를 주면 LAYER1_EMPTY_WAITS 전에는 화면만 보고 기다린다.
    """
    show = show or {}
    if (show.get("observation") or {}).get("agentWait"):
        return _d("human", reason="prompt_wait")       # agentWait 은 양성 신호로만 믿는다
    tail = _read_tail(read)
    if tail and BLOCKED_RE.search("\n".join(_tail("\n".join(tail)))):
        # 실측(T-007): codex 가 승인창에서 멈췄는데 agentWait 은 비어 있었다 — 화면이 유일한 증거다
        return _d("human", reason="blocked_prompt")
    if empty_waits is not None and empty_waits < LAYER1_EMPTY_WAITS:
        return _d("wait", reason="layer1")
    p = (worker or {}).get("projection") or {}
    na = p.get("nextAction") or {}
    if (p.get("attention") or {}).get("requiresAction") and na.get("kind") not in (None, "none") and na.get("argv"):
        return _d("run_argv", argv=["orca"] + list(na["argv"]), kind=na["kind"])   # argv 엔 실행 파일명이 없다
    if (p.get("liveness") or {}).get("verdict") == "exited":
        return _d("human", reason="exited")
    last = (show.get("terminal") or {}).get("lastOutputAt")
    if last is None:
        return _d("wait", reason="no_output_timestamp")
    if now_ms - last >= STALL_MS[role]:
        return _d("human", reason="stalled", silent_ms=now_ms - last)
    return _d("wait", silent_ms=now_ms - last)


def reviewer_model(config_text, cfg=None):
    """리뷰 워커(codex) 기동 인자. model·effort 는 relay 설정 파일(cfg, models.load_all 결과)에서만 온다.

    codex 의 config.toml 은 사전 조건 키(Orca 가 codex 준비를 감지하는 데 쓴다)만 확인하고, 그 안의 model 은 쓰지 않는다 —
    codex 를 평소 용도로 쓰는 모델과 리뷰어 모델을 따로 관리하기 위해서다 (ADR 0002).
    """
    if tomllib is None:
        raise ValueError("Python 3.11+ 가 필요하다 (tomllib)")
    c = tomllib.loads(config_text)
    missing = []
    if c.get("check_for_update_on_startup") is not False:
        missing.append("check_for_update_on_startup = false")
    if "app-name" not in ((c.get("tui") or {}).get("terminal_title") or []):
        missing.append("tui.terminal_title 에 app-name")
    if missing:
        return _d("human", reason="codex_prereq_missing", missing=missing)
    r = models.resolve("reviewer", cfg or {})
    if not r["model"]:
        return _d("human", reason="reviewer_model_unset")
    return _d("launch", agent="codex", model=r["model"], effort=r["effort"])


def implementer_model(cfg=None, agy_models_text=None):
    """구현 워커(agy) worker-start --agent antigravity 인자. model 이 없으면 agy 기본 모델 — --model 을 주지 않는다.

    agy_models_text(agy models 출력)를 주면 agy 가 실행 즉시 거부할 조합(없는 모델, 레벨이 이름에 든 모델 + effort)을 미리 잡는다.
    """
    r = models.resolve("implementer", cfg or {})
    if r["effort"] and not r["model"]:
        # Orca: worker-start 의 --effort 는 --model 이 있어야 한다 — 조용히 버리지 않는다
        return _d("human", reason="effort_needs_model",
                  detail="worker-start 는 --effort 를 --model 없이 받지 않는다 — implementer.model 을 함께 적는다")
    if agy_models_text is not None:
        status, detail, _fix = models.check_agy(r["model"], r["effort"], agy_models_text)
        if status == "fail":
            return _d("human", reason="agy_model_invalid", detail=detail)
    return _d("launch", agent="antigravity", model=r["model"], effort=r["effort"],
              source="relay_models" if r["configured"] else "agy_default")


def coordinator_model(cfg=None):
    """진행자 워커 기동 인자. 설계 세션이 worker-start --agent claude 의 --model·--effort 로 그대로 준다 (ADR 0004)."""
    r = models.resolve("coordinator", cfg or {})
    return _d("launch", agent="claude", model=r["model"], effort=r["effort"],
              source="relay_models" if r["configured"] else "default")


def session_model(role, cfg=None):
    """설계자(사람이 연 Claude 세션). 플러그인이 /model 을 대신 칠 수 없어 사람이 따를 명령만 돌려준다."""
    r = models.resolve(role, cfg or {})
    return _d("session", role=role, model=r["model"], effort=r["effort"],
              command=models.session_command(r["model"], r["effort"]),
              source="relay_models" if r["configured"] else "default")
