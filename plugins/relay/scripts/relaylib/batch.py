# -*- coding: utf-8 -*-
"""일괄 진행 시작 검사 — 진행 목록을 만들고 모든 이슈를 검사한다."""
import collections
import heapq
import json

from relaylib import handoff, issue


def _check(name, status, detail, fix=""):
    return {"name": name, "status": status, "detail": detail, "fix": fix}


def exit_code(checks):
    """FAIL 이 하나라도 있으면 1, 아니면 0."""
    return 1 if any(c.get("status") == "fail" for c in checks) else 0


def _parse_paginated(out):
    """gh api --paginate 출력(페이지별 JSON 배열이 이어짐) 파싱."""
    text = (out or "").strip()
    if not text:
        return []
    decoder = json.JSONDecoder()
    pos = 0
    items = []
    while pos < len(text):
        while pos < len(text) and text[pos].isspace():
            pos += 1
        if pos >= len(text):
            break
        obj, end_pos = decoder.raw_decode(text, idx=pos)
        if isinstance(obj, list):
            items.extend(obj)
        elif isinstance(obj, dict):
            items.append(obj)
        pos = end_pos
    return items


def plan(issue_ref, run):
    """구현 이슈 → {"order": [{"number": n, "url": u, "title": t}], "checks": [...], "field": "일괄 진행: #a #b"}.
    시작 이슈를 읽지 못하거나 local-markdown 참조면 issue.IssueError."""
    ref = issue.parse(issue_ref)
    if ref["kind"] != "github":
        raise issue.IssueError("일괄 진행은 GitHub 이슈만 지원한다: %s" % issue_ref)
    start_issue = issue.fetch(ref, run)
    owner = ref["owner"]
    repo = ref["repo"]
    start_num = ref["number"]

    checks = []
    if start_issue.get("parent") is not None:
        checks.append(_check(
            "start",
            "fail",
            "#%d 은 하위 이슈(태스크)다 — 부모 구현 이슈 URL 로 시작한다" % start_num,
        ))
        return {"order": [], "checks": checks, "field": "일괄 진행:"}

    queue = collections.deque([start_num])
    visited = set()
    enqueued = {start_num}
    all_nodes = {start_num}
    states = {start_num: start_issue.get("state", "open")}
    issue_info = {start_num: start_issue}
    edges = set()  # (u, v): u blocks v
    seen_repo_fails = set()

    while queue:
        curr = queue.popleft()
        if curr in visited:
            continue
        visited.add(curr)

        rc_bb, out_bb = run(["gh", "api", "--paginate", "repos/%s/%s/issues/%d/dependencies/blocked_by" % (owner, repo, curr)])
        rc_bl, out_bl = run(["gh", "api", "--paginate", "repos/%s/%s/issues/%d/dependencies/blocking" % (owner, repo, curr)])

        if rc_bb != 0 or rc_bl != 0:
            if curr == start_num:
                raise issue.IssueError("시작 이슈의 의존 API 를 읽지 못했다: %s" % ref["url"])
            checks.append(_check("read:#%d" % curr, "fail", "이슈 #%d 의 의존 API 를 읽지 못했다" % curr))
            continue

        try:
            items_bb = _parse_paginated(out_bb)
            items_bl = _parse_paginated(out_bl)
        except ValueError:
            if curr == start_num:
                raise issue.IssueError("gh api 출력이 JSON 이 아니다: %s" % ref["url"])
            checks.append(_check("read:#%d" % curr, "fail", "이슈 #%d 의 의존 API 출력이 JSON 이 아니다" % curr))
            continue

        # blocked_by: neighbor blocks curr (nbr -> curr)
        for it in items_bb:
            nbr_url = it.get("html_url", "")
            m = issue.GH_RE.match(nbr_url)
            if not m:
                continue
            nbr_owner, nbr_repo, nbr_num_str = m.group(1), m.group(2), m.group(3)
            nbr_num = int(nbr_num_str)
            if (nbr_owner, nbr_repo) != (owner, repo):
                fail_key = (curr, nbr_owner, nbr_repo, nbr_num)
                if fail_key not in seen_repo_fails:
                    seen_repo_fails.add(fail_key)
                    checks.append(_check(
                        "repo:#%d" % curr,
                        "fail",
                        "#%d 이 다른 저장소 이슈 %s/%s#%d 와 blocking 으로 이어져 있다" %
                        (curr, nbr_owner, nbr_repo, nbr_num),
                    ))
                continue
            nbr_state = it.get("state", "open")
            if nbr_num not in states:
                states[nbr_num] = nbr_state
            all_nodes.add(nbr_num)
            edges.add((nbr_num, curr))
            if nbr_num not in enqueued:
                enqueued.add(nbr_num)
                queue.append(nbr_num)

        # blocking: curr blocks neighbor (curr -> nbr)
        for it in items_bl:
            nbr_url = it.get("html_url", "")
            m = issue.GH_RE.match(nbr_url)
            if not m:
                continue
            nbr_owner, nbr_repo, nbr_num_str = m.group(1), m.group(2), m.group(3)
            nbr_num = int(nbr_num_str)
            if (nbr_owner, nbr_repo) != (owner, repo):
                fail_key = (curr, nbr_owner, nbr_repo, nbr_num)
                if fail_key not in seen_repo_fails:
                    seen_repo_fails.add(fail_key)
                    checks.append(_check(
                        "repo:#%d" % curr,
                        "fail",
                        "#%d 이 다른 저장소 이슈 %s/%s#%d 와 blocking 으로 이어져 있다" %
                        (curr, nbr_owner, nbr_repo, nbr_num),
                    ))
                continue
            nbr_state = it.get("state", "open")
            if nbr_num not in states:
                states[nbr_num] = nbr_state
            all_nodes.add(nbr_num)
            edges.add((curr, nbr_num))
            if nbr_num not in enqueued:
                enqueued.add(nbr_num)
                queue.append(nbr_num)

    excluded_from_order = set()
    failed_reads = set()
    for n in sorted(all_nodes):
        if states.get(n) == "open":
            if n not in issue_info:
                ref_n = {"kind": "github", "owner": owner, "repo": repo, "number": n, "url": "https://github.com/%s/%s/issues/%d" % (owner, repo, n)}
                try:
                    it = issue.fetch(ref_n, run)
                    issue_info[n] = it
                    states[n] = it.get("state", "open")
                except issue.IssueError:
                    checks.append(_check("read:#%d" % n, "fail", "이슈를 읽지 못했다: #%d" % n))
                    failed_reads.add(n)
                    excluded_from_order.add(n)
                    continue

            if n in issue_info and issue_info[n].get("parent") is not None:
                checks.append(_check(
                    "task-edge:#%d" % n,
                    "fail",
                    "열린 하위 이슈 #%d 이 진행 목록에 이어졌다 — 하위 이슈의 blocking 은 자기 구현 이슈 안에서만 쓴다" % n,
                ))
                excluded_from_order.add(n)

    adj = collections.defaultdict(list)
    in_degree = {n: 0 for n in all_nodes}
    for u, v in edges:
        if u in all_nodes and v in all_nodes:
            adj[u].append(v)
            in_degree[v] += 1

    ready = [n for n in all_nodes if in_degree[n] == 0]
    heapq.heapify(ready)

    sorted_nodes = []
    while ready:
        curr = heapq.heappop(ready)
        sorted_nodes.append(curr)
        for v in adj[curr]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                heapq.heappush(ready, v)

    cycle_detected = False
    if len(sorted_nodes) < len(all_nodes):
        cycle_detected = True
        cycle_nodes = sorted(n for n in all_nodes if in_degree[n] > 0)
        checks.append(_check(
            "list",
            "fail",
            "blocking 순환: %s" % " ".join("#%d" % x for x in cycle_nodes),
        ))
        order = []
    else:
        order = []
        for n in sorted_nodes:
            if n not in excluded_from_order and states.get(n) == "open":
                it = issue_info.get(n)
                order.append({
                    "number": n,
                    "url": it["url"] if it else ("https://github.com/%s/%s/issues/%d" % (owner, repo, n)),
                    "title": it["title"] if it else "",
                })

    if not cycle_detected:
        if len(order) == 0:
            checks.append(_check("list", "fail", "열린 구현 이슈가 없다"))
        else:
            checks.append(_check(
                "list",
                "ok",
                "%d개: %s" % (len(order), " ".join("#%d" % x["number"] for x in order)),
            ))

    for item in order:
        num = item["number"]
        u = item["url"]

        try:
            h_res = handoff.check(u, run)
            for c in h_res.get("checks", []):
                prefixed_name = "#%d %s" % (num, c["name"])
                checks.append(_check(prefixed_name, c["status"], c["detail"], c.get("fix", "")))
        except issue.IssueError:
            checks.append(_check("read:#%d" % num, "fail", "이슈를 읽지 못했다: #%d" % num))
            continue

        try:
            subs = handoff.sub_issues(issue.parse(u), run)
        except issue.IssueError:
            checks.append(_check("read:#%d" % num, "fail", "하위 이슈를 읽지 못했다: #%d" % num))
            continue

        if subs:
            sub_nums = {s["number"] for s in subs}
            seen_task_edge_fails = set()
            for s in subs:
                s_num = s["number"]
                rc_sbb, out_sbb = run(["gh", "api", "--paginate", "repos/%s/%s/issues/%d/dependencies/blocked_by" % (owner, repo, s_num)])
                rc_sbl, out_sbl = run(["gh", "api", "--paginate", "repos/%s/%s/issues/%d/dependencies/blocking" % (owner, repo, s_num)])
                if rc_sbb != 0 or rc_sbl != 0:
                    checks.append(_check("read:#%d" % s_num, "fail", "이슈 #%d 의 의존 API 를 읽지 못했다" % s_num))
                    continue

                try:
                    items_sbb = _parse_paginated(out_sbb)
                    items_sbl = _parse_paginated(out_sbl)
                except ValueError:
                    checks.append(_check("read:#%d" % s_num, "fail", "이슈 #%d 의 의존 API 출력이 JSON 이 아니다" % s_num))
                    continue

                sub_nbr_items = items_sbb + items_sbl

                for nbr in sub_nbr_items:
                    nbr_url = nbr.get("html_url", "")
                    m = issue.GH_RE.match(nbr_url)
                    if not m:
                        x_num = nbr.get("number")
                        fail_key = (s_num, x_num)
                        if fail_key not in seen_task_edge_fails:
                            seen_task_edge_fails.add(fail_key)
                            checks.append(_check(
                                "task-edge:#%d" % num,
                                "fail",
                                "태스크 #%d 가 구현 이슈 밖의 #%s 와 blocking 으로 이어져 있다" % (s_num, x_num),
                            ))
                    else:
                        nbr_owner, nbr_repo, nbr_num_str = m.group(1), m.group(2), m.group(3)
                        x_num = int(nbr_num_str)
                        if (nbr_owner, nbr_repo) != (owner, repo) or x_num not in sub_nums:
                            fail_key = (s_num, x_num)
                            if fail_key not in seen_task_edge_fails:
                                seen_task_edge_fails.add(fail_key)
                                checks.append(_check(
                                    "task-edge:#%d" % num,
                                    "fail",
                                    "태스크 #%d 가 구현 이슈 밖의 #%d 와 blocking 으로 이어져 있다" % (s_num, x_num),
                                ))

        human = h_res.get("human")
        if human and human.get("before"):
            count = len(human["before"])
            checks.append(_check(
                "before-merge:#%d" % num,
                "fail",
                "「사람이 할 일」 `머지 전:` 에 할 일 %d개 — 일괄 진행은 시작하지 않는다" % count,
                fix="지금 하고 `없음` 으로 고치거나, `머지 뒤:` 로 옮기거나, 그 이슈를 relay:handoff 로 따로 돌린다",
            ))

    if order:
        field = "일괄 진행: " + " ".join("#%d" % x["number"] for x in order)
    else:
        field = "일괄 진행:"

    return {"order": order, "checks": checks, "field": field}
