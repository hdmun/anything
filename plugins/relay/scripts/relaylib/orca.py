# -*- coding: utf-8 -*-
"""orca 응답·화면 해석 결정기 — SKILL (d)(e) 의 정본.

결정만 돌려준다. orca 명령 조립은 SKILL.md 가 Orca 정본 가이드를 따라 한다 (ADR 0001).
모든 근거는 실측(poker-server T-004, T-005)이다 — 테스트 픽스처에 남아 있다.
"""
import re

from relaylib import models

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
    r"|permission required|requires permission|allow once|allow always|run this command\?|\bsign in\b"
    # codex 명령 승인창 (실측 T-007: git status --short, Get-Location 에서 멈춤)
    r"|would you like to run the following command|yes, proceed|don'?t ask again",
    re.I,
)
AGY_SIGNED_IN = "OAuth: authenticated successfully"

# agy 를 띄우는 terminal create --command 값. 맨 앞 토큰이 `agy` 면 Orca 가 시작 명령을 에이전트로 인식해
# 다른 경로로 띄우는데, 그 경로에선 입력창(`>` 줄)이 출력 스트림에 남지 않아 tui-idle 이 영영 통과하지 못한다
# (1.3.3: 11/11 실패, 1.2.17: 간헐 실패). 아무 일도 안 하는 PowerShell 문장을 앞에 두면 일반 셸 명령으로 실행되어
# 1.2.17·1.3.3 모두 7/7 통과, worker-start --terminal 도 정상 연결됐다 (2026-10-10, Orca 1.4.222). Orca 터미널 셸이 PowerShell 이라는 전제다.
AGY_LAUNCH_COMMAND = "$null=1; agy"


def agy_launch_command(model=None, effort=None):
    """AGY_LAUNCH_COMMAND 뒤에 설정 파일의 model·effort 를 붙인다. 값은 models.check_value 를 통과한 것만 받는다.

    앞의 `$null=1;` 는 그대로 둔다 — 뒤에 인자가 붙어도 맨 앞 토큰은 `$null=1;` 라 Orca 가 에이전트 시작 경로로 가로채지 않는다.
    """
    cmd = AGY_LAUNCH_COMMAND
    if model:
        models.check_value("implementer", "model", model)
        cmd += " --model " + model
    if effort:
        models.check_value("implementer", "effort", effort)
        cmd += " --effort " + effort
    return cmd


AGY_HEADER = "antigravity cli"
AGY_IDLE_RE = re.compile(r"\bidle\b", re.I)
LAYER1_EMPTY_WAITS = 3        # 이 횟수 전에는 화면 확인만 하고 그냥 기다린다 (SKILL (e) 1층)


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


def _has_prompt(lines, agent):
    for l in lines:
        s = l.strip()
        if s == ">" or (agent == "codex" and s.startswith("›")):
            return True
    return False


def is_bare_agy(command):
    """맨 앞 토큰이 agy 인 시작 명령 — Orca 가 에이전트 시작 경로로 띄워 tui-idle 이 통과하지 못한다."""
    first = (command or "").strip().strip("'\"").split(" ")[0].lower()
    return first in ("agy", "agy.exe") or first.endswith(("\\agy", "/agy", "\\agy.exe", "/agy.exe"))


def readiness(screen, agent, retries, log=None, recreated=False, command=None, launch_command=None):
    """tui-idle timeout 이후의 사다리. retries 는 이미 다시 건 tui-idle 횟수, command 는 terminal create --command 값.

    launch_command 는 재생성할 때 권하는 명령(설정 파일의 model·effort 를 반영). 없으면 AGY_LAUNCH_COMMAND.
    """
    launch_command = launch_command or AGY_LAUNCH_COMMAND
    tail = _tail(screen)
    if BLOCKED_RE.search("\n".join(tail)):
        return _d("human", reason="blocked_prompt")
    if agent == "antigravity" and log is not None and AGY_SIGNED_IN not in log:
        return _d("human", reason="not_signed_in")
    if agent == "antigravity" and is_bare_agy(command):
        # 기다려도 풀리지 않는다(실측 T-007: 9회 연속 timeout) — 재시도 없이 올바른 명령으로 다시 만든다
        if recreated:
            return _d("human", reason="bare_launch_command", launch_command=launch_command)
        return _d("recreate_terminal", reason="bare_launch_command", launch_command=launch_command)
    if agent == "antigravity" and AGY_HEADER not in screen.lower() and _has_prompt(tail, agent) \
            and AGY_IDLE_RE.search("\n".join(tail)):
        # 실측(T-007 수정 라운드): 긴 세션 뒤 같은 터미널에서 tui-idle 3회 연속 timeout, 화면은 `>`·Idle 정상.
        # Orca 는 보관하는 꼬리(최대 2000줄)에서 `antigravity cli` 머리글을 찾는데 그게 밀려났다 — 기다려도 안 돌아온다
        if recreated:
            return _d("human", reason="header_scrolled_out")
        return _d("recreate_terminal", reason="header_scrolled_out", launch_command=launch_command)
    if retries < TUI_IDLE_RETRIES:
        return _d("retry_tui_idle", wait_seconds=TUI_IDLE_RETRY_SECONDS, attempt=retries + 1)
    if not _has_prompt(tail, agent):
        return _d("human", reason="no_prompt")
    if recreated:
        return _d("human", reason="recreate_failed")
    # 올바른 명령인데도 화면엔 입력창이 있고 Orca 가 못 알아본다 — 드문 경우다. 한 번만 새로 만든다
    return _d("recreate_terminal")


def liveness(worker, terminal, role, now_ms, screen=None, empty_waits=None):
    """빈 대기 뒤의 판정 (SKILL (e)). worker 는 worker-list 항목, terminal 은 terminal show 결과, screen 은 terminal read --screen.

    empty_waits(연속 빈 대기 횟수)를 주면 LAYER1_EMPTY_WAITS 전에는 화면만 보고 기다린다.
    """
    terminal = terminal or {}
    if terminal.get("agentWait"):
        return _d("human", reason="prompt_wait")       # agentWait 은 양성 신호로만 믿는다
    if screen and BLOCKED_RE.search("\n".join(_tail(screen))):
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
    last = terminal.get("lastOutputAt")
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


def codex_launch_command(model, effort):
    """리뷰 워커를 터미널로 먼저 띄우는 명령 (SKILL 의 codex 절차와 같다). --yolo 를 빼면 worker_done 보고가 멈춘다 (2026-10-11 실측)."""
    models.check_value("reviewer", "model", model)
    models.check_value("reviewer", "effort", effort)
    return "codex --yolo -m %s -c model_reasoning_effort=%s" % (model, effort)


def implementer_model(cfg=None, agy_models_text=None):
    """구현 워커(agy) 기동 인자. model 이 없으면 agy 기본 모델 — 명령에 --model 을 붙이지 않는다.

    agy_models_text(agy models 출력)를 주면 agy 가 실행 즉시 거부할 조합(없는 모델, 레벨이 이름에 든 모델 + effort)을 미리 잡는다.
    """
    r = models.resolve("implementer", cfg or {})
    if agy_models_text is not None:
        status, detail, _fix = models.check_agy(r["model"], r["effort"], agy_models_text)
        if status == "fail":
            return _d("human", reason="agy_model_invalid", detail=detail)
    return _d("launch", agent="antigravity", model=r["model"], effort=r["effort"],
              launch_command=agy_launch_command(r["model"], r["effort"]),
              source="relay_models" if r["configured"] else "agy_default")


def session_model(role, cfg=None):
    """설계자·진행자(Claude 세션). 플러그인이 /model 을 대신 칠 수 없어 사람·진행자가 따를 명령만 돌려준다."""
    r = models.resolve(role, cfg or {})
    return _d("session", role=role, model=r["model"], effort=r["effort"],
              command=models.session_command(r["model"], r["effort"]),
              source="relay_models" if r["configured"] else "default")
