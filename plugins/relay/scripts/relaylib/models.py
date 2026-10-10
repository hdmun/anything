# -*- coding: utf-8 -*-
"""역할별 model·effort 설정 — 로드, 검증, 우선순위 해석.

파일 두 개를 필드 단위로 겹친다 (뒤가 앞을 덮는다):
  1. ~/.relay/models.json        사용자 전역 — 계정·쿼터에 따른 개인 선호
  2. <repo>/.ai/relay-models.json 저장소별 — 팀이 통일하거나 이 저장소만 다르게 할 때

둘 다 없거나 필드가 비어 있으면 값이 None 이다. 그 경우 호출자가 기존 동작으로 되돌아간다
(구현자는 agy 기본 모델, effort 는 역할 기본값). 리뷰어 model 만은 기본값이 없다 —
codex config.toml 의 model 로 되돌아가지 않는다 (ADR 0002).

model 은 셸 명령줄(codex -m, agy --model)에 그대로 들어가므로 문자 집합을 제한한다.
"""
import json
import pathlib
import re

USER_PATH = pathlib.Path.home() / ".relay" / "models.json"
REPO_REL = ".ai/relay-models.json"

ROLES = ("designer", "coordinator", "implementer", "reviewer")
FIELDS = ("model", "effort")

_CLAUDE_EFFORTS = ("low", "medium", "high", "xhigh", "max")
EFFORTS = {
    "designer": _CLAUDE_EFFORTS,
    "coordinator": _CLAUDE_EFFORTS,
    "implementer": ("low", "medium", "high", "xhigh", "max"),   # agy --help
    "reviewer": ("minimal", "low", "medium", "high", "xhigh"),  # codex model_reasoning_effort
}
DEFAULT_EFFORT = {"designer": "high", "coordinator": "medium", "implementer": None, "reviewer": "high"}

MODEL_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]*$")


class ModelsError(Exception):
    """설정 파일이 잘못됐다. CLI 는 종료코드 2로 보고한다."""


def check_value(role, field, value, where="값"):
    if field == "model":
        if not isinstance(value, str) or not MODEL_RE.match(value):
            raise ModelsError("%s: %s.model 은 영문·숫자·._:/- 만 쓸 수 있다 (받은 값: %r)" % (where, role, value))
    elif value not in EFFORTS[role]:
        raise ModelsError("%s: %s.effort 는 %s 중 하나여야 한다 (받은 값: %r)" % (where, role, "|".join(EFFORTS[role]), value))


def parse(text, where="models.json"):
    """JSON 텍스트 → {role: {model?, effort?}}. 모르는 역할·필드는 오타 방지를 위해 거부한다. null·빈 문자열은 '지정 안 함'."""
    try:
        raw = json.loads(text)
    except ValueError as e:
        raise ModelsError("%s: JSON 오류 (%s)" % (where, e))
    if not isinstance(raw, dict):
        raise ModelsError("%s: 최상위는 객체여야 한다" % where)
    out = {}
    for role, spec in raw.items():
        if role.startswith("$"):
            continue
        if role not in ROLES:
            raise ModelsError("%s: 모르는 역할 %r (허용: %s)" % (where, role, ", ".join(ROLES)))
        if not isinstance(spec, dict):
            raise ModelsError("%s: %s 는 객체여야 한다" % (where, role))
        bad = [k for k in spec if k not in FIELDS and not k.startswith("$")]
        if bad:
            raise ModelsError("%s: %s 에 모르는 필드 %s (허용: %s)" % (where, role, ", ".join(bad), ", ".join(FIELDS)))
        kept = {}
        for f in FIELDS:
            v = spec.get(f)
            if v is None or v == "":
                continue
            check_value(role, f, v, where)
            kept[f] = v
        out[role] = kept
    return out


def load(path):
    """파일이 없으면 {}. 있는데 잘못이면 ModelsError."""
    p = pathlib.Path(path)
    if not p.is_file():
        return {}
    return parse(p.read_text(encoding="utf-8"), where=str(p))


def merge(*layers):
    """layers 는 낮은 우선순위부터. 필드 단위로 덮는다."""
    out = {}
    for layer in layers:
        for role, spec in layer.items():
            out.setdefault(role, {}).update(spec)
    return out


def load_all(repo=None, user_path=None):
    """(병합 결과, 읽은 파일 목록). repo 가 None 이면 사용자 파일만."""
    user = pathlib.Path(user_path) if user_path else USER_PATH
    layers, used = [], []
    paths = [user] + ([pathlib.Path(repo) / REPO_REL] if repo else [])
    for p in paths:
        d = load(p)
        if p.is_file():
            used.append(str(p))
        layers.append(d)
    return merge(*layers), used


def resolve(role, cfg):
    """{'model': 설정값 또는 None, 'effort': 설정값 또는 역할 기본값 또는 None, 'configured': 설정 파일이 준 필드 목록}."""
    spec = cfg.get(role) or {}
    return {
        "model": spec.get("model"),
        "effort": spec.get("effort") or DEFAULT_EFFORT[role],
        "configured": sorted(spec),
    }


def session_command(model, effort):
    """Claude 세션(설계자·진행자)을 설정대로 띄우는 명령. 플러그인이 /model 을 대신 칠 수 없어 안내만 한다."""
    parts = ["claude"]
    if model:
        parts += ["--model", model]
    if effort:
        parts += ["--effort", effort]
    return " ".join(parts)


# ---- agy 모델 목록 대조 (agy models 출력) -------------------------------------------------

_LEVELS = ("low", "medium", "high", "xhigh", "max")


def parse_agy_models(text):
    """`agy models` 출력 → {기본 모델 ID: [가능한 effort], ...}와 {레벨이 붙은 정식 ID} 의 튜플.

    줄 형식은 '<id>\\t<label>'. id 끝의 -low/-medium/-high 가 effort 다.
    """
    ids = []
    for line in (text or "").splitlines():
        first = line.split("\t", 1)[0].strip()
        if "\t" in line and MODEL_RE.match(first):
            ids.append(first)
    bases = {}
    for i in ids:
        head, _, tail = i.rpartition("-")
        if head and tail in _LEVELS:
            bases.setdefault(head, []).append(tail)
    return bases, set(ids)


def check_agy(model, effort, agy_models_text):
    """(status, detail, fix). agy 가 실행 즉시 거부하는 조합을 미리 잡는다 — 거부되면 기동 실패 예산을 쓴다."""
    bases, ids = parse_agy_models(agy_models_text)
    if not ids:
        return "warn", "agy models 출력을 읽지 못해 모델·effort 를 대조하지 못했다", "agy models 를 직접 실행해 본다"
    if model is None:
        return "ok", "구현자: agy 기본 모델" + (" / effort %s" % effort if effort else ""), ""
    if model in ids:
        if effort:
            return ("fail", "%s 는 effort 가 이름에 들어 있는 모델이라 effort=%s 와 함께 쓸 수 없다 (agy: conflicts with --effort)" % (model, effort),
                    "model 을 기본 이름(예: %s)으로 바꾸거나 effort 를 지운다" % model.rpartition("-")[0])
        return "ok", "구현자: %s (agy models 에 있음)" % model, ""
    if model not in bases:
        return "fail", "agy models 에 없는 모델: %s" % model, "agy models 로 목록을 확인한다 (기본 이름 예: %s)" % ", ".join(sorted(bases)[:3])
    if effort and effort not in bases[model]:
        return "fail", "%s 는 effort %s 를 지원하지 않는다 (가능: %s)" % (model, effort, ", ".join(sorted(bases[model], key=_LEVELS.index))), "effort 를 바꾼다"
    return "ok", "구현자: %s / %s" % (model, effort or "기본 effort"), ""
