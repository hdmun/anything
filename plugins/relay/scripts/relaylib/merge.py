# -*- coding: utf-8 -*-
"""머지 조건과 일괄 진행 완료 보고 (ADR 0006·0007)."""
import json
import pathlib
import re

from relaylib import handoff, issue, resume


def _check(name, status, detail, fix=""):
    return {"name": name, "status": status, "detail": detail, "fix": fix}


def check(issue_ref, worktree, run, git, base="origin/main"):
    """머지 조건 1~3 → {"checks": [...]}. run(argv) -> (rc, stdout), git(worktree, *args) -> stdout."""
    h_res = handoff.check(issue_ref, run)
    tasks = h_res.get("tasks", [])
    human = h_res.get("human")
    ref = issue.parse(issue_ref)
    root_tid = issue.task_id(ref)

    checks = []

    # 1. done:<태스크 ID>
    git_out = git(worktree, "log", "--format=%(trailers:key=" + resume.TRAILER + ",valueonly)", "%s..HEAD" % base)
    done = resume.done_tasks(git_out.splitlines())
    for t in tasks:
        tid = t["task"]
        if tid in done:
            checks.append(_check("done:" + tid, "ok", "Relay-Done 있음"))
        else:
            checks.append(_check("done:" + tid, "fail", "Relay-Done 이 없다"))

    # 2. snapshot:<태스크 ID>
    specs_dir = pathlib.Path(worktree) / ".ai" / "specs"
    for t in tasks:
        tid = t["task"]
        matched = sorted(specs_dir.glob("%s-*.md" % tid)) if specs_dir.is_dir() else []
        if len(matched) != 1:
            checks.append(_check("snapshot:" + tid, "fail", "스냅숏 파일이 %d개다" % len(matched)))
            continue

        spec_file = matched[0]
        content = spec_file.read_text(encoding="utf-8")
        s_body = issue.snapshot_body(content)
        if s_body is None:
            checks.append(_check("snapshot:" + tid, "fail", "스냅숏 형식을 읽지 못했다"))
            continue

        t_ref = issue.parse(t["url"])
        t_issue = issue.fetch(t_ref, run)
        cur_body = t_issue.get("body") or ""

        s_norm = s_body.replace("\r\n", "\n").rstrip("\n")
        cur_norm = cur_body.replace("\r\n", "\n").rstrip("\n")

        if s_norm == cur_norm:
            checks.append(_check("snapshot:" + tid, "ok", "본문 일치"))
        else:
            checks.append(_check("snapshot:" + tid, "fail", "태스크 도중 이슈 본문이 바뀌었다 — 반영되지 않은 채 머지하지 않는다"))

    # 3. before-merge:<구현 이슈 ID>
    b_name = "before-merge:" + root_tid
    if human is None:
        checks.append(_check(b_name, "fail", "「사람이 할 일」 절을 읽지 못했다"))
    else:
        before = human.get("before") or []
        if len(before) == 0:
            checks.append(_check(b_name, "ok", "머지 전 할 일 없음"))
        else:
            checks.append(_check(b_name, "fail", "`머지 전:` 에 할 일 %d개" % len(before)))

    return {"checks": checks}


def exit_code(checks):
    """FAIL 이 하나라도 있으면 1, 아니면 0."""
    return 1 if any(c.get("status") == "fail" for c in checks) else 0


def parse_list(text):
    """"#12 #14 #15" 또는 "12,14,15" → [12, 14, 15]. 형식 오류면 ValueError."""
    if not isinstance(text, str):
        raise ValueError("문자열이어야 한다")
    s = text.strip()
    if s.startswith("일괄 진행:"):
        s = s[len("일괄 진행:"):].strip()
    if not s:
        raise ValueError("목록이 비어 있다")
    tokens = [t for t in re.split(r"[\s,]+", s.strip(", \t\n\r")) if t]
    if not tokens:
        raise ValueError("목록이 비어 있다")
    numbers = []
    for t in tokens:
        m = re.match(r"^#?(\d+)$", t)
        if not m:
            raise ValueError("형식 오류: %r" % t)
        numbers.append(int(m.group(1)))
    return numbers


def report(issue_ref, numbers, run):
    """완료 보고 → {"body": 텍스트, "issues": [{"number": n, "pr": URL 또는 None, "after": 개수 또는 None}]}"""
    ref = issue.parse(issue_ref)
    if ref["kind"] != "github":
        raise issue.IssueError("일괄 진행은 GitHub 이슈만 지원한다: %s" % issue_ref)
    owner = ref["owner"]
    repo = ref["repo"]

    issues = []
    for n in numbers:
        item_url = "https://github.com/%s/%s/issues/%d" % (owner, repo, n)
        item_ref = {"kind": "github", "owner": owner, "repo": repo, "number": n, "url": item_url}

        # PR: gh issue view <이슈 URL> --json closedByPullRequestsReferences
        pr = None
        rc, out = run(["gh", "issue", "view", item_url, "--json", "closedByPullRequestsReferences"])
        if rc == 0:
            try:
                data = json.loads(out)
                refs = data.get("closedByPullRequestsReferences") or []
                if refs and isinstance(refs, list):
                    pr = refs[-1].get("url")
            except (ValueError, TypeError):
                pr = None

        # 머지 뒤 할 일: issue.fetch 본문 → handoff.human_todo → after 의 개수
        after = None
        try:
            it = issue.fetch(item_ref, run)
            todo, probs = handoff.human_todo(it.get("body") or "")
            if not probs and todo is not None:
                after = len(todo.get("after") or [])
        except Exception:
            after = None

        issues.append({"number": n, "pr": pr, "after": after})

    lines = [
        "relay 완료 보고 — 일괄 진행 " + " ".join("#%d" % n for n in numbers),
        "",
    ]
    for item in issues:
        pr_str = item["pr"] if item["pr"] else "머지된 PR 없음"
        if item["after"] is None:
            todo_str = "머지 뒤 할 일 읽지 못함"
        elif item["after"] == 0:
            todo_str = "머지 뒤 할 일 없음"
        else:
            todo_str = "머지 뒤 할 일 %d개" % item["after"]
        lines.append("- #%d: %s · %s" % (item["number"], pr_str, todo_str))

    body = "\n".join(lines) + "\n"
    return {"body": body, "issues": issues}
