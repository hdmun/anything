# -*- coding: utf-8 -*-
"""기동 전 검사 — `relay:handoff` 가 진행자 세션을 띄우기 전에 구현 이슈 하나를 본다 (ADR 0007).

검사 셋: 태스크 수(하위 이슈 ≤ MAX_TASKS), 템플릿 필수 절(변경 대상 파일, 인수 조건의 게이트 명령), 작성자 권한(ADR 0006), 「사람이 할 일」 절.
실패를 모두 모아 돌려준다 — handoff 는 doctor 와 이것을 끝까지 돌려 한 번에 보고한다.
머신 상태는 보지 않는다(그것은 doctor 의 몫이다).
"""
import json
import re

from relaylib import issue

MAX_TASKS = 5
FILES_HEADING = "## 변경 대상 파일"
ACCEPT_HEADING = "## 인수 조건"
HUMAN_HEADING = "## 사람이 할 일"
_BULLET_RE = re.compile(r"^\s*[-*]\s+\S")
_GATE_RE = re.compile(r"게이트 명령\s*:?\s*`([^`]+)`")
_HUMAN_LINE_RE = re.compile(r"^(\s*)(?:[-*]\s+)?머지 (전|뒤)\s*:\s*(.*)$")
_BULLET_LINE_RE = re.compile(r"^(\s*)[-*]\s+(.*)$")
_CHECKBOX_PREFIX_RE = re.compile(r"^\[[ xX]\]\s*")


def _check(name, status, detail, fix=""):
    return {"name": name, "status": status, "detail": detail, "fix": fix}


def _section(body, heading):
    """heading 아래 다음 `## ` 까지의 줄들. 절이 없으면 None. HTML 주석은 지운다."""
    text = re.sub(r"<!--.*?-->", "", (body or "").replace("\r\n", "\n"), flags=re.S)
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.strip() == heading:
            out = []
            for l in lines[i + 1:]:
                if l.startswith("## "):
                    break
                out.append(l)
            return out
    return None


def human_todo(body):
    """「사람이 할 일」 절 → (todo, problems).
    todo = {"before": [항목 글], "after": [항목 글]} — 값이 정확히 `없음` 이면 빈 목록.
    problems = [문제 문자열]. 문제가 하나라도 있으면 todo 는 None. 절이 없으면 (None, ["「사람이 할 일」 절이 없다"])."""
    lines = _section(body, HUMAN_HEADING)
    if lines is None:
        return None, ["「사람이 할 일」 절이 없다"]

    matches = []
    for idx, line in enumerate(lines):
        m = _HUMAN_LINE_RE.match(line)
        if m:
            matches.append((idx, len(m.group(1)), m.group(2), m.group(3).strip()))

    before_matches = [m for m in matches if m[2] == "전"]
    after_matches = [m for m in matches if m[2] == "뒤"]

    problems = []

    def parse_entry(kind_label, kind_matches):
        heading_name = "머지 " + kind_label
        if len(kind_matches) == 0:
            problems.append("`%s:` 줄이 없다" % heading_name)
            return []
        if len(kind_matches) > 1:
            problems.append("`%s:` 줄이 %d개다" % (heading_name, len(kind_matches)))
            return []

        idx, header_indent, _, val = kind_matches[0]
        sub_lines = []
        for l in lines[idx + 1:]:
            if not l.strip():
                continue
            indent = len(l) - len(l.lstrip())
            if indent <= header_indent:
                break
            sub_lines.append(l)

        bullet_matches = []
        for sl in sub_lines:
            bm = _BULLET_LINE_RE.match(sl)
            if bm:
                bullet_matches.append((len(bm.group(1)), bm.group(2)))

        sub_items = []
        if bullet_matches:
            min_indent = min(indent for indent, _ in bullet_matches)
            for indent, text in bullet_matches:
                if indent == min_indent:
                    t = _CHECKBOX_PREFIX_RE.sub("", text).strip()
                    sub_items.append(t)

        is_val_placeholder = val.startswith("<") and val.endswith(">")
        has_sub_placeholder = any(it.startswith("<") and it.endswith(">") for it in sub_items)
        if is_val_placeholder or has_sub_placeholder:
            problems.append("`%s:` 에 자리표시(<…>)가 남아 있다" % heading_name)

        if val == "없음":
            if sub_items:
                problems.append("`%s:` 이 `없음` 인데 하위 항목이 있다" % heading_name)
            return []
        elif val:
            return [val] + sub_items
        else:
            if not sub_items:
                problems.append("`%s:` 에 값이 없다" % heading_name)
            return sub_items

    before_items = parse_entry("전", before_matches)
    after_items = parse_entry("뒤", after_matches)

    if problems:
        return None, problems
    return {"before": before_items, "after": after_items}, []


def template_problems(body):
    """필수 절의 문제 목록. 문제가 없으면 []."""
    problems = []
    files = _section(body, FILES_HEADING)
    if files is None:
        problems.append("「%s」 절이 없다" % FILES_HEADING[3:])
    elif not any(_BULLET_RE.match(l) and "<" not in l and "path/to/" not in l for l in files):
        problems.append("「%s」 절에 파일 목록이 없다" % FILES_HEADING[3:])
    accept = _section(body, ACCEPT_HEADING)
    if accept is None:
        problems.append("「%s」 절이 없다" % ACCEPT_HEADING[3:])
    else:
        gates = [m.group(1).strip() for l in accept for m in [_GATE_RE.search(l)] if m]
        if not any(g and not (g.startswith("<") and g.endswith(">")) for g in gates):
            problems.append("「%s」 절에 실행 가능한 `게이트 명령: \\`...\\`` 줄이 없다" % ACCEPT_HEADING[3:])
    return problems


def sub_issues(ref, run):
    """GitHub 하위 이슈 → [ref]. local-markdown 은 하위 이슈가 없다(이슈 자체가 태스크)."""
    if ref["kind"] != "github":
        return []
    rc, out = run(["gh", "api", "repos/%s/%s/issues/%d/sub_issues" % (ref["owner"], ref["repo"], ref["number"])])
    if rc != 0:
        raise issue.IssueError("하위 이슈를 읽지 못했다: %s" % ref["url"])
    try:
        items = json.loads(out)
    except ValueError:
        raise issue.IssueError("gh api 출력이 JSON 이 아니다: %s" % ref["url"])
    return [issue.parse(it["html_url"]) for it in items if it.get("html_url")]


def check(issue_ref, run):
    """구현 이슈 → {"checks": [...], "tasks": [{task, url, title}],
                    "human": {"url": <절을 읽은 이슈 URL>, "before": [...], "after": [...]} 또는 None}.
    입력 오류(참조·읽기 실패)는 IssueError."""
    ref = issue.parse(issue_ref)
    parent = issue.fetch(ref, run)
    subs = sub_issues(ref, run)
    checks = []

    count = len(subs) or 1
    if count > MAX_TASKS:
        checks.append(_check("tasks", "fail", "태스크 %d개 — 구현 이슈 하나는 %d개 이하다" % (count, MAX_TASKS),
                             "구현 이슈를 나눈다 (태스크를 나누는 것은 설계 세션의 몫이다)"))
    else:
        checks.append(_check("tasks", "ok", "태스크 %d개%s" % (count, " (하위 이슈)" if subs else " (이슈 자체)")))

    targets = [(r, issue.fetch(r, run)) for r in subs] if subs else [(ref, parent)]
    if subs:   # 묶음 이슈는 스냅숏하지 않지만 작성자는 본다 — PR 제목·본문이 여기서 온다
        p = issue.author_problem(ref, parent)
        checks.append(_check("author:" + issue.task_id(ref), "fail" if p else "ok",
                             "작성자 %s" % parent.get("author_association"),
                             "쓰기 권한자(OWNER·MEMBER·COLLABORATOR)가 쓴 이슈만 받는다" if p else ""))

    tasks = []
    for r, it in targets:
        tid = issue.task_id(r)
        tasks.append({"task": tid, "url": it["url"], "title": it["title"]})
        probs = template_problems(it["body"])
        checks.append(_check("template:" + tid, "fail" if probs else "ok",
                             "; ".join(probs) if probs else "필수 절 있음",
                             "relay:spec 의 references/spec-template.md 형식으로 이슈 본문을 고친다" if probs else ""))
        if r["kind"] == "github":
            p = issue.author_problem(r, it)
            checks.append(_check("author:" + tid, "fail" if p else "ok", "작성자 %s" % it.get("author_association"),
                                 "쓰기 권한자(OWNER·MEMBER·COLLABORATOR)가 쓴 이슈만 받는다" if p else ""))

    # 「사람이 할 일」 검사
    todo, probs = human_todo(parent.get("body"))
    hid = issue.task_id(ref)
    if probs:
        checks.append(_check("human:" + hid, "fail", "; ".join(probs),
                             "relay:spec 의 references/spec-template.md 의 「사람이 할 일」 절 형식으로 고친다"))
    else:
        b_cnt = "머지 전 %d개" % len(todo["before"]) if todo["before"] else "머지 전 없음"
        a_cnt = "머지 뒤 %d개" % len(todo["after"]) if todo["after"] else "머지 뒤 없음"
        checks.append(_check("human:" + hid, "ok", "%s · %s" % (b_cnt, a_cnt)))

    if subs:
        for r, it in targets:
            if _section(it.get("body"), HUMAN_HEADING) is not None:
                checks.append(_check("human-misplaced:" + issue.task_id(r), "fail",
                                     "하위 이슈에 「사람이 할 일」 절이 있다",
                                     "「사람이 할 일」 절을 부모 이슈로 옮긴다"))

    human = {"url": parent["url"], "before": todo["before"], "after": todo["after"]} if todo is not None else None
    return {"checks": checks, "tasks": tasks, "human": human}


def exit_code(checks):
    return 1 if any(c["status"] == "fail" for c in checks) else 0
