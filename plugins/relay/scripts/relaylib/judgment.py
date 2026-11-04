# -*- coding: utf-8 -*-
"""판정 서브에이전트의 출력 검증 — references/judgment-schema.json 과 같은 규칙 (ADR 0008, #23).

판정은 spec 안에서만 한다. spec 이 틀렸거나 spec 에 없는 결정이 필요하면 `stop` 이다.
진행자는 검증에 실패하면 서브에이전트를 한 번 다시 부르고, 또 실패하면 멈춤 보고를 한다.
"""
import json
import pathlib
import re

DECISIONS = {
    "spec_violation": ("fix_impl", "dismiss", "stop"),
    "repeated_finding": ("another_round", "accept", "stop"),
    "question": ("answer", "stop"),
}
# 태스크를 성공으로 끝내는 판정 — 판정 기록 커밋에 Relay-Done 을 붙인다 (ADR 0010)
DONE = ("dismiss", "accept")
FIELDS = ("reason", "decision", "rationale", "instruction", "stop_summary")
JUDGMENT_RE = re.compile(r"^(I-[a-z0-9-]+)\.j(\d+)\.json$")


def validate(j, reason=None):
    """오류 문자열 목록(비면 통과). reason 을 주면 판정의 reason 과 같아야 한다."""
    if not isinstance(j, dict):
        return ["최상위가 객체가 아니다"]
    errs = ["스키마에 없는 필드: %s" % k for k in j if k not in FIELDS]
    for k in ("reason", "decision", "rationale"):
        if k not in j:
            errs.append("필수 필드 없음: %s" % k)
    for k in FIELDS:
        if k in j and (not isinstance(j[k], str) or not j[k].strip()):
            errs.append("%s 는 비어 있지 않은 문자열이어야 한다" % k)
    r = j.get("reason")
    if r not in DECISIONS:
        errs.append("reason 값이 잘못됐다: %r (허용: %s)" % (r, ", ".join(DECISIONS)))
        return errs
    if reason and r != reason:
        errs.append("reason 이 맡긴 사유와 다르다: %r != %r" % (r, reason))
    d = j.get("decision")
    if d not in DECISIONS[r]:
        errs.append("%s 의 decision 은 %s 중 하나다 (받은 값: %r)" % (r, "|".join(DECISIONS[r]), d))
    if d == "stop":
        if "stop_summary" not in j:
            errs.append("decision 이 stop 이면 stop_summary(멈춤 보고 한 줄)가 필수다")
    else:
        if "instruction" not in j:
            errs.append("decision 이 %s 이면 instruction 이 필수다" % d)
        if "stop_summary" in j:
            errs.append("stop_summary 는 decision 이 stop 일 때만 쓴다")
    return errs


def check_file(path, reason=None):
    """판정 파일 → 오류 목록. 파일이 없으면 OSError(입력 오류)."""
    text = pathlib.Path(path).read_text(encoding="utf-8")
    try:
        j = json.loads(text)
    except ValueError as e:
        return ["JSON 파싱 실패: %s" % e]
    return validate(j, reason)
