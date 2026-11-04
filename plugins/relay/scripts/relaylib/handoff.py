# -*- coding: utf-8 -*-
"""기동 전 검사 — `relay:handoff` 가 진행자 세션을 띄우기 전에 구현 이슈 하나를 본다 (ADR 0007).

검사 셋: 태스크 수(하위 이슈 ≤ MAX_TASKS), 템플릿 필수 절(변경 대상 파일, 인수 조건의 게이트 명령), 작성자 권한(ADR 0006).
실패를 모두 모아 돌려준다 — handoff 는 doctor 와 이것을 끝까지 돌려 한 번에 보고한다.
머신 상태는 보지 않는다(그것은 doctor 의 몫이다).
"""
import json
import re

from relaylib import issue

MAX_TASKS = 5
FILES_HEADING = "## 변경 대상 파일"
ACCEPT_HEADING = "## 인수 조건"
_BULLET_RE = re.compile(r"^\s*[-*]\s+\S")
_GATE_RE = re.compile(r"게이트 명령\s*:?\s*`([^`]+)`")


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
    """구현 이슈 → {"checks": [...], "tasks": [{task, url, title}]}. 입력 오류(참조·읽기 실패)는 IssueError."""
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
                             "relay:handoff 의 references/spec-template.md 형식으로 이슈 본문을 고친다" if probs else ""))
        if r["kind"] == "github":
            p = issue.author_problem(r, it)
            checks.append(_check("author:" + tid, "fail" if p else "ok", "작성자 %s" % it.get("author_association"),
                                 "쓰기 권한자(OWNER·MEMBER·COLLABORATOR)가 쓴 이슈만 받는다" if p else ""))
    return {"checks": checks, "tasks": tasks}


def exit_code(checks):
    return 1 if any(c["status"] == "fail" for c in checks) else 0
