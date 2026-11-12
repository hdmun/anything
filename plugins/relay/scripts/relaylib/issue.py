# -*- coding: utf-8 -*-
"""구현 이슈 읽기와 spec 스냅숏 — ADR 0006·0007 의 정본.

정본은 트래커의 구현 이슈다. 진행자는 태스크를 시작할 때 이슈 본문을 워크트리의 `.ai/specs/` 에
스냅숏(고정 사본)으로 남긴다. 스냅숏에는 본문만 넣고 코멘트는 넣지 않는다(프롬프트 주입 대책).
GitHub 이슈는 작성자가 쓰기 권한자일 때만 스냅숏한다. local-markdown 이슈는 저장소 안 파일이라 권한을 보지 않는다.
"""
import datetime
import json
import pathlib
import re

TRUSTED = ("OWNER", "MEMBER", "COLLABORATOR")
GH_RE = re.compile(r"^https://github\.com/([^/\s]+)/([^/\s]+)/issues/(\d+)/?$")
LOCAL_RE = re.compile(r"(?:^|[\\/])\.scratch[\\/]([a-z0-9-]+)[\\/]issues[\\/](\d+)-[^\\/]*\.md$", re.I)
SLUG_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class IssueError(Exception):
    """입력 오류(알 수 없는 이슈 참조, 트래커 읽기 실패). CLI 는 종료코드 2."""


def parse(ref):
    """이슈 URL 또는 local-markdown 경로 → 참조 dict."""
    ref = (ref or "").strip()
    m = GH_RE.match(ref)
    if m:
        return {"kind": "github", "owner": m.group(1), "repo": m.group(2), "number": int(m.group(3)), "url": ref.rstrip("/")}
    m = LOCAL_RE.search(ref.replace("\\", "/"))
    if m:
        return {"kind": "local", "feature": m.group(1).lower(), "number": int(m.group(2)), "path": ref}
    raise IssueError("이슈 참조를 알 수 없다: %r — GitHub 이슈 URL 이나 .scratch/<feature>/issues/<NN>-<slug>.md 경로" % ref)


def task_id(ref):
    """태스크 ID (ADR 0007): GitHub 은 I-<이슈 번호>, local-markdown 은 I-<feature>-<NN>."""
    if ref["kind"] == "github":
        return "I-%d" % ref["number"]
    return "I-%s-%02d" % (ref["feature"], ref["number"])


def fetch(ref, run):
    """이슈 → {url, title, body, updated_at, author_association, state, parent}. run(argv)->(rc, stdout)."""
    if ref["kind"] == "github":
        rc, out = run(["gh", "api", "repos/%s/%s/issues/%d" % (ref["owner"], ref["repo"], ref["number"])])
        if rc != 0:
            raise IssueError("이슈를 읽지 못했다: %s" % ref["url"])
        try:
            d = json.loads(out)
        except ValueError:
            raise IssueError("gh api 출력이 JSON 이 아니다: %s" % ref["url"])
        p_url = d.get("parent_issue_url")
        parent = None
        if p_url:
            try:
                parent = int(str(p_url).rstrip("/").split("/")[-1])
            except ValueError:
                parent = None
        return {"url": d.get("html_url") or ref["url"], "title": d.get("title") or "", "body": d.get("body") or "",
                "updated_at": d.get("updated_at"), "author_association": d.get("author_association"),
                "state": d.get("state") or "open", "parent": parent}
    p = pathlib.Path(ref["path"])
    if not p.is_file():
        raise IssueError("이슈 파일이 없다: %s" % p)
    text = p.read_text(encoding="utf-8")
    lines = text.splitlines()
    title = next((l[2:].strip() for l in lines if l.startswith("# ")), p.stem)
    body = "\n".join(l for l in lines if not (l.startswith("# ") and l[2:].strip() == title)).strip("\n")
    mtime = datetime.datetime.fromtimestamp(p.stat().st_mtime, datetime.timezone.utc)
    return {"url": str(p), "title": title, "body": body,
            "updated_at": mtime.strftime("%Y-%m-%dT%H:%M:%SZ"), "author_association": None,
            "state": "open", "parent": None}


def author_problem(ref, issue):
    """작성자 권한 (ADR 0006). 문제가 없으면 None."""
    if ref["kind"] != "github":
        return None
    a = issue.get("author_association")
    if a not in TRUSTED:
        return "author_not_trusted"
    return None


def render(issue):
    """스냅숏 본문. 머리말이 사본임을 밝힌다 — 리뷰어는 이 파일을 git 에서 읽는다."""
    return ("> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.\n"
            "> 이슈: %s\n"
            "> updatedAt: %s\n"
            "\n"
            "# %s\n"
            "\n"
            "%s\n") % (issue["url"], issue["updated_at"], issue["title"], issue["body"].replace("\r\n", "\n").rstrip("\n"))


def snapshot_body(text):
    """spec 스냅숏 파일 내용 → 본문(render 의 역). 형식이 다르면 None."""
    if not isinstance(text, str):
        return None
    text = text.replace("\r\n", "\n")
    lines = text.split("\n")

    title_idx = None
    for i, line in enumerate(lines):
        if line.startswith("# "):
            title_idx = i
            break
    if title_idx is None:
        return None

    header_lines = lines[:title_idx]
    has_quote = False
    for line in header_lines:
        s = line.strip()
        if not s:
            continue
        if s.startswith(">"):
            has_quote = True
        else:
            return None
    if not has_quote:
        return None

    if title_idx + 1 >= len(lines):
        return None
    if lines[title_idx + 1] != "":
        return None

    body_lines = lines[title_idx + 2:]
    body = "\n".join(body_lines)
    if body.endswith("\n"):
        body = body[:-1]
    return body


def snapshot(issue_ref, worktree, slug, run):
    """이슈를 읽어 `.ai/specs/<ID>-<slug>.md` 를 쓴다. 결정 dict 를 돌려준다(커밋은 진행자가 한다)."""
    if not SLUG_RE.match(slug or ""):
        raise IssueError("슬러그는 영문 소문자·숫자·하이픈만: %r" % slug)
    ref = parse(issue_ref)
    issue = fetch(ref, run)
    tid = task_id(ref)
    problem = author_problem(ref, issue)
    if problem:
        return {"action": "human", "reason": problem, "task": tid, "author_association": issue.get("author_association")}
    rel = ".ai/specs/%s-%s.md" % (tid, slug)
    path = pathlib.Path(worktree) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render(issue), encoding="utf-8", newline="\n")
    return {"action": "commit", "task": tid, "path": rel, "updatedAt": issue["updated_at"]}
