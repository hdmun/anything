# -*- coding: utf-8 -*-
"""리뷰 리포트 검증과 심각도·라운드 분기 — SKILL (g)(h) 의 정본.

decide() 는 결정만 돌려준다. 그 결정을 orca 명령으로 옮기는 일은 SKILL.md 가 한다 (ADR 0001).

  success   게이트·리뷰 통과. 리포트 커밋 후 성공 종료 (i)
  fix_round 새 Task + 새 Dispatch 로 수정 라운드 (g)
  escalate  설계 세션(Opus)으로 — decision gate (h)
  human     사람 호출, 태스크 중단 (h)
  rewrite   리포트 형식 위반 — 리뷰어에게 재작성 요구
"""
import json
import pathlib
import re

SEVERITIES = ("SPEC_VIOLATION", "BLOCKER", "MAJOR", "MINOR")
BLOCKING = ("SPEC_VIOLATION", "BLOCKER", "MAJOR")
VERDICTS = ("pass", "changes_requested")
TOP_REQUIRED = ("taskId", "verdict", "findings")
FINDING_FIELDS = ("severity", "file", "line", "summary", "repro", "specRef")
FINDING_REQUIRED = ("severity", "file", "summary", "repro")

MAX_REVIEW_ROUNDS = 3
MAX_TOTAL_ROUNDS = 5

REPORT_RE = re.compile(r"^(T-\d+)\.r(\d+)\.json$")


class ReviewError(Exception):
    """입력 오류(리포트 없음, 경로 오류). CLI 는 종료코드 2."""


def validate(r, expected_task=None):
    """review-schema.json 과 같은 규칙. 오류 문자열 목록(비면 통과)."""
    if not isinstance(r, dict):
        return ["최상위가 객체가 아니다"]
    errs = []
    for k in TOP_REQUIRED:
        if k not in r:
            errs.append("최상위 필수 필드 없음: %s" % k)
    for k in r:
        if k not in TOP_REQUIRED:
            errs.append("스키마에 없는 최상위 필드: %s" % k)
    if "taskId" in r and not isinstance(r["taskId"], str):
        errs.append("taskId 가 문자열이 아니다")
    elif expected_task and r.get("taskId") != expected_task:
        errs.append("taskId 가 파일명과 다르다: %r != %r" % (r.get("taskId"), expected_task))
    if "verdict" in r and r["verdict"] not in VERDICTS:
        errs.append("verdict 값이 잘못됐다: %r (허용: %s)" % (r["verdict"], ", ".join(VERDICTS)))
    findings = r.get("findings", [])
    if not isinstance(findings, list):
        return errs + ["findings 가 배열이 아니다"]
    for i, f in enumerate(findings):
        errs.extend("findings[%d]: %s" % (i, e) for e in _validate_finding(f))
    sevs = {f.get("severity") for f in findings if isinstance(f, dict)}
    blocking = sevs & set(BLOCKING)
    if r.get("verdict") == "pass" and blocking:
        errs.append("verdict 가 pass 인데 %s 가 있다" % "/".join(sorted(blocking)))
    if r.get("verdict") == "changes_requested" and not blocking:
        errs.append("verdict 가 changes_requested 인데 SPEC_VIOLATION/BLOCKER/MAJOR 가 없다 — MINOR 만이면 pass")
    return errs


def _validate_finding(f):
    if not isinstance(f, dict):
        return ["객체가 아니다"]
    errs = ["필수 필드 없음: %s" % k for k in FINDING_REQUIRED if k not in f]
    errs += ["스키마에 없는 필드: %s" % k for k in f if k not in FINDING_FIELDS]
    if "severity" in f and f["severity"] not in SEVERITIES:
        errs.append("severity 값이 잘못됐다: %r" % (f["severity"],))
    for k in ("file", "summary", "repro", "specRef"):
        if k in f and not isinstance(f[k], str):
            errs.append("%s 가 문자열이 아니다" % k)
    if "line" in f and (isinstance(f["line"], bool) or not isinstance(f["line"], int)):
        errs.append("line 이 정수가 아니다")
    if f.get("severity") == "SPEC_VIOLATION" and "specRef" not in f:
        errs.append("SPEC_VIOLATION 에는 specRef 가 필수다")
    return errs


def load_report(path):
    """(리포트, 오류 목록). JSON 이 깨졌으면 리포트는 None."""
    path = pathlib.Path(path)
    m = REPORT_RE.match(path.name)
    try:
        r = json.loads(path.read_text(encoding="utf-8"))
    except ValueError as e:
        return None, ["JSON 파싱 실패: %s" % e]
    return r, validate(r, expected_task=m.group(1) if m else None)


def reports(reviews_dir, task):
    """[(라운드 번호, 경로)] — 번호 순(r10 이 r9 뒤)."""
    d = pathlib.Path(reviews_dir)
    if not d.is_dir():
        raise ReviewError("리뷰 디렉터리가 없다: %s" % d)
    out = []
    for p in d.iterdir():
        m = REPORT_RE.match(p.name)
        if m and m.group(1) == task:
            out.append((int(m.group(2)), p))
    return sorted(out)


def _norm(s):
    return " ".join(str(s).split()).lower()


def _blocking_keys(r):
    return {(_norm(f.get("file", "")), _norm(f.get("summary", "")))
            for f in r.get("findings", []) if isinstance(f, dict) and f.get("severity") in BLOCKING}


def _d(action, **kw):
    # action 을 맨 앞에 — 진행자는 첫 키만 읽어도 분기할 수 있다
    return dict(action=action, **kw)


def decide(reviews_dir, task, impl_rounds):
    found = reports(reviews_dir, task)
    if not found:
        raise ReviewError("%s 의 리뷰 리포트가 없다: %s/%s.r*.json" % (task, reviews_dir, task))
    n, path = found[-1]
    base = {"report": str(path), "review_rounds": len(found), "impl_rounds": impl_rounds}

    r, errs = load_report(path)
    if errs:
        return _d("rewrite", **base, errors=errs)

    sevs = {f["severity"] for f in r["findings"]}
    if not sevs & set(BLOCKING):
        return _d("success", **base)

    total = impl_rounds + len(found)
    if total > MAX_TOTAL_ROUNDS:
        return _d("human", **base, reason="total_round_limit")
    if "SPEC_VIOLATION" in sevs:
        return _d("escalate", **base, reason="spec_violation")
    if len(found) >= 2:
        prev, _ = load_report(found[-2][1])
        if prev and _blocking_keys(prev) & _blocking_keys(r):
            return _d("escalate", **base, reason="repeated_finding")
    if len(found) > MAX_REVIEW_ROUNDS:
        return _d("escalate", **base, reason="review_round_limit")
    return _d("fix_round", **base, round=n + 1,
                severities=sorted(sevs & set(BLOCKING), key=SEVERITIES.index))
