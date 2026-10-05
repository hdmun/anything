# -*- coding: utf-8 -*-
"""orca 응답·화면 해석 결정기 — SKILL (d)(e) 의 정본.

결정만 돌려준다. orca 명령 조립은 SKILL.md 가 Orca 정본 가이드를 따라 한다 (ADR 0001).
모든 근거는 실측(poker-server T-004, T-005)이다 — 테스트 픽스처에 남아 있다.
"""
import re

try:
    import tomllib
except ImportError:  # pragma: no cover — Python < 3.11
    tomllib = None

STARTUP_BUDGET = 2            # 같은 Task 계열의 기동 실패 허용 횟수 (Orca 는 3회째에 circuit-break)
TUI_IDLE_RETRIES = 3
TUI_IDLE_RETRY_SECONDS = 30
STALL_MS = {"implementer": 5 * 60_000, "reviewer": 10 * 60_000}
SCREEN_TAIL_LINES = 15        # 답한 프롬프트가 스크롤백에 남아도 오판하지 않게 화면 맨 아래만 본다

# Orca 의 TERMINAL_WAIT_BLOCKED_SENTINEL_RE 와 같은 계열 + agy 로그인 요구.
# 'sign in' 은 단어 경계로만 — 시작 직후 찍히는 'not signed in' 배너는 차단이 아니다.
BLOCKED_RE = re.compile(
    r"update available|choose working directory to|codex just got an upgrade|hooks need review|do you trust"
    r"|trust this|trusted workspace|press enter to (?:confirm|continue|view|insert)|press t to trust"
    r"|permission required|requires permission|allow once|allow always|run this command\?|\bsign in\b",
    re.I,
)
AGY_SIGNED_IN = "OAuth: authenticated successfully"


def _d(action, **kw):
    return dict(action=action, **kw)


def startup(resp, prior_failures=0):
    """worker-start 응답 → 다음 행동. ok 는 믿지 않는다 — 준비 감지 실패도 ok:true 로 온다(T-005)."""
    if not resp.get("ok"):
        code = (resp.get("error") or {}).get("code", "unknown")
        if code == "agent_unconfigured":
            # 터미널에 agentIdentity 가 붙기 전 — tui-idle 을 먼저 통과시킨다. Task 는 아직 멀쩡하다
            return _d("wait_tui_idle", reason=code)
        if code == "task_not_startable":
            return _d("new_task", reason=code, task_failed=True)
        return _d("human", reason=code)

    r = resp.get("result") or {}
    failed = r.get("failedStage")
    if failed:
        err = r.get("lastError")
        if err == "agent_prompt_blocked":
            return _d("human", reason="agent_prompt_blocked", stage=failed)   # 프롬프트 자동 응답 금지
        if prior_failures + 1 >= STARTUP_BUDGET:
            return _d("human", reason="startup_budget", stage=failed, error=err, task_failed=True)
        # agent_readiness 한 번으로 Task 는 failed 다 — 재출발은 항상 새 Task
        return _d("new_task", stage=failed, error=err, task_failed=True)

    dispatch = r.get("dispatch") or {}
    did = dispatch.get("id") if isinstance(dispatch, dict) else None
    model = ((r.get("launch") or {}).get("effective") or {}).get("model")
    if did:
        return _d("ok", dispatch=did, model=model)
    return _d("lookup_dispatch", model=model)


def _tail(screen):
    lines = [l.rstrip() for l in screen.splitlines()]
    while lines and not lines[-1].strip():
        lines.pop()
    return lines[-SCREEN_TAIL_LINES:]


def _has_prompt(lines, agent):
    for l in lines:
        s = l.strip()
        if s == ">" or (agent == "codex" and s.startswith("›")):
            return True
    return False


def readiness(screen, agent, retries, log=None, recreated=False):
    """tui-idle timeout 이후의 사다리. retries 는 이미 다시 건 tui-idle 횟수."""
    tail = _tail(screen)
    if BLOCKED_RE.search("\n".join(tail)):
        return _d("human", reason="blocked_prompt")
    if agent == "antigravity" and log is not None and AGY_SIGNED_IN not in log:
        return _d("human", reason="not_signed_in")
    if retries < TUI_IDLE_RETRIES:
        return _d("retry_tui_idle", wait_seconds=TUI_IDLE_RETRY_SECONDS, attempt=retries + 1)
    if not _has_prompt(tail, agent):
        return _d("human", reason="no_prompt")
    if recreated:
        return _d("human", reason="recreate_failed")
    # 화면엔 입력창이 있는데 Orca 가 못 알아본다 — 그리기 순서 경합(T-004). 한 번만 새로 만든다
    return _d("recreate_terminal")


def liveness(worker, terminal, role, now_ms):
    """빈 대기 3회 뒤의 판정 (SKILL (e) 2·3층). worker 는 worker-list 항목, terminal 은 terminal show 결과."""
    terminal = terminal or {}
    if terminal.get("agentWait"):
        return _d("human", reason="prompt_wait")       # agentWait 은 양성 신호로만 믿는다
    p = worker.get("projection") or {}
    na = p.get("nextAction") or {}
    if (p.get("attention") or {}).get("requiresAction") and na.get("kind") not in (None, "none") and na.get("argv"):
        return _d("run_argv", argv=["orca"] + list(na["argv"]), kind=na["kind"])   # argv 엔 실행 파일명이 없다
    if (p.get("liveness") or {}).get("verdict") == "exited":
        return _d("human", reason="exited")
    last = terminal.get("lastOutputAt")
    if last is None:
        return _d("wait", reason="no_output_timestamp")
    if now_ms - last >= STALL_MS[role]:
        return _d("human", reason="stalled", silent_ms=now_ms - last)
    return _d("wait", silent_ms=now_ms - last)


def reviewer_model(config_text):
    """~/.codex/config.toml → 리뷰 워커 기동 인자. 모델은 codex 기본 모델을 따른다 (모델 계열)."""
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
    if not c.get("model"):
        return _d("human", reason="codex_model_unset")
    return _d("launch", agent="codex", model=c["model"], effort="high")
