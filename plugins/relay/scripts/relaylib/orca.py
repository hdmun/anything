# -*- coding: utf-8 -*-
"""워커 기동 인자 결정기 — SKILL (d) 의 정본.

결정만 돌려준다. orca 명령 조립은 에이전트가 Orca 가이드를 읽고 한다 (ADR 0001·0003).
워커는 worker-start --agent 로 띄운다 — 결정기는 그 인자(agent·model·effort)를 돌려줄 뿐 명령줄을 만들지 않는다.
기동 영수증·대기·무응답은 Orca 의 깨우기와 영수증을 그대로 따른다 — relay 가 해석하지 않는다 (ADR 0009).
"""
from relaylib import models

try:
    import tomllib
except ImportError:  # pragma: no cover — Python < 3.11
    tomllib = None


def _d(action, **kw):
    return dict(action=action, **kw)


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
