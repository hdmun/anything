# -*- coding: utf-8 -*-
"""batch-plan 단위 테스트 — 진행 목록 생성과 검사 (엣지 케이스 표 1~18)."""
import io
import json
import unittest
from unittest.mock import patch

import helpers  # noqa: F401
import relay_cli
from relaylib import batch, issue

TASK_GOOD = """## 배경

본문

## 변경 대상 파일

- `src/hand.rs` — 수정

## 인수 조건

- [ ] Ante 를 받는다
- [ ] 게이트 명령: `cargo test --release` — 종료코드로 판정한다
"""

GOOD_BODY = TASK_GOOD + """
## 사람이 할 일

- 머지 전: 없음
- 머지 뒤: 없음
"""


def url(n):
    return "https://github.com/hdmun/poker-server/issues/%d" % n


def make_tracker(
    issues=None,
    edges=None,
    subs=None,
    fail_fetch=(),
    fail_dep=(),
    other_repos=None,
):
    issues = issues or {}
    edges = edges or []
    subs = subs or {}
    other_repos = other_repos or {}

    calls = []

    def run(argv):
        calls.append(argv)
        path = None
        for a in argv:
            if a.startswith("repos/"):
                path = a
                break
        if not path:
            return 1, ""

        parts = path.split("/")
        n = int(parts[4])

        if len(parts) == 5:
            if n in fail_fetch:
                return 1, ""
            info = issues.get(n, {})
            if isinstance(info, tuple):
                body, state, parent, assoc = info
            elif isinstance(info, dict):
                body = info.get("body", GOOD_BODY)
                state = info.get("state", "open")
                parent = info.get("parent", None)
                assoc = info.get("author_association", "OWNER")
            else:
                body = GOOD_BODY
                state = "open"
                parent = None
                assoc = "OWNER"
            parent_url = ("https://api.github.com/repos/hdmun/poker-server/issues/%d" % parent) if parent else None
            return 0, json.dumps({
                "html_url": url(n),
                "title": "이슈 %d" % n,
                "body": body,
                "updated_at": "2026-11-05T00:00:00Z",
                "author_association": assoc,
                "state": state,
                "parent_issue_url": parent_url,
            })

        if parts[5] == "sub_issues":
            sub_list = subs.get(n, [])
            return 0, json.dumps([{"html_url": url(s)} for s in sub_list])

        if parts[5] == "dependencies":
            dep_type = parts[6]
            if n in fail_dep or (n, dep_type) in fail_dep:
                return 1, ""

            items = []
            if n in other_repos and dep_type in other_repos[n]:
                items.extend(other_repos[n][dep_type])

            if dep_type == "blocked_by":
                for u, v in edges:
                    if v == n:
                        u_info = issues.get(u, {})
                        u_state = u_info.get("state", "open") if isinstance(u_info, dict) else (u_info[1] if isinstance(u_info, tuple) else "open")
                        items.append({
                            "number": u,
                            "state": u_state,
                            "html_url": url(u),
                            "repository_url": "https://api.github.com/repos/hdmun/poker-server",
                        })
            elif dep_type == "blocking":
                for u, v in edges:
                    if u == n:
                        v_info = issues.get(v, {})
                        v_state = v_info.get("state", "open") if isinstance(v_info, dict) else (v_info[1] if isinstance(v_info, tuple) else "open")
                        items.append({
                            "number": v,
                            "state": v_state,
                            "html_url": url(v),
                            "repository_url": "https://api.github.com/repos/hdmun/poker-server",
                        })
            return 0, json.dumps(items)

        return 1, ""

    run.calls = calls
    return run


class EdgeCases(unittest.TestCase):
    def test_01_single_issue(self):
        run = make_tracker(issues={12: {}})
        res = batch.plan(url(12), run)
        order = [x["number"] for x in res["order"]]
        self.assertEqual(order, [12])
        self.assertEqual(batch.exit_code(res["checks"]), 0)
        self.assertEqual(res["field"], "일괄 진행: #12")

    def test_02_linear_chain(self):
        run = make_tracker(issues={12: {}, 14: {}, 15: {}}, edges=[(12, 14), (14, 15)])
        res = batch.plan(url(12), run)
        self.assertEqual([x["number"] for x in res["order"]], [12, 14, 15])
        self.assertEqual(batch.exit_code(res["checks"]), 0)
        self.assertEqual(res["field"], "일괄 진행: #12 #14 #15")

    def test_03_linear_chain_start_from_middle(self):
        run = make_tracker(issues={12: {}, 14: {}, 15: {}}, edges=[(12, 14), (14, 15)])
        res = batch.plan(url(14), run)
        self.assertEqual([x["number"] for x in res["order"]], [12, 14, 15])
        self.assertEqual(batch.exit_code(res["checks"]), 0)

    def test_04_resume_closed_node_fork(self):
        # 12(닫힘) -> 14, 12 -> 15. 14 로 시작 -> [14, 15]
        run = make_tracker(issues={12: {"state": "closed"}, 14: {}, 15: {}}, edges=[(12, 14), (12, 15)])
        res = batch.plan(url(14), run)
        self.assertEqual([x["number"] for x in res["order"]], [14, 15])
        self.assertEqual(batch.exit_code(res["checks"]), 0)

    def test_05_resume_closed_node_chain(self):
        # 12(닫힘) -> 14 -> 15. 14 로 시작 -> [14, 15]
        run = make_tracker(issues={12: {"state": "closed"}, 14: {}, 15: {}}, edges=[(12, 14), (14, 15)])
        res = batch.plan(url(14), run)
        self.assertEqual([x["number"] for x in res["order"]], [14, 15])
        self.assertEqual(batch.exit_code(res["checks"]), 0)

    def test_06_tie_break_by_number(self):
        # 12 -> 20, 12 -> 15 (20, 15 사이 간선 없음) -> [12, 15, 20]
        run = make_tracker(issues={12: {}, 15: {}, 20: {}}, edges=[(12, 20), (12, 15)])
        res = batch.plan(url(12), run)
        self.assertEqual([x["number"] for x in res["order"]], [12, 15, 20])
        self.assertEqual(batch.exit_code(res["checks"]), 0)

    def test_07_resume_closed_in_middle(self):
        # 12 -> 14(닫힘) -> 15 -> [12, 15]
        run = make_tracker(issues={12: {}, 14: {"state": "closed"}, 15: {}}, edges=[(12, 14), (14, 15)])
        res = batch.plan(url(12), run)
        self.assertEqual([x["number"] for x in res["order"]], [12, 15])
        self.assertEqual(batch.exit_code(res["checks"]), 0)

    def test_08_other_repository_dependency(self):
        run = make_tracker(
            issues={12: {}},
            other_repos={12: {"blocking": [{"number": 99, "state": "open", "html_url": "https://github.com/other-org/other-repo/issues/99"}]}},
        )
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        repo_fails = [c for c in res["checks"] if c["name"] == "repo:#12" and c["status"] == "fail"]
        self.assertTrue(repo_fails)
        self.assertIn("other-org/other-repo#99", repo_fails[0]["detail"])

    def test_09_open_sub_issue_in_graph(self):
        # 12 -> 30, 30 은 열린 하위 이슈 -> task-edge:#30 FAIL, order 에 30 없음
        run = make_tracker(issues={12: {}, 30: {"parent": 10}}, edges=[(12, 30)])
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        self.assertEqual([x["number"] for x in res["order"]], [12])
        task_edge_fails = [c for c in res["checks"] if c["name"] == "task-edge:#30" and c["status"] == "fail"]
        self.assertTrue(task_edge_fails)

    def test_10_sub_issue_edge_outside_parent(self):
        # 12 의 하위 이슈 13 -> 40 (40 은 12 의 하위 이슈가 아님) -> task-edge:#12 FAIL
        run = make_tracker(
            issues={12: {}, 13: {"parent": 12}, 40: {}},
            subs={12: [13]},
            edges=[(13, 40)],
        )
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        task_edge_fails = [c for c in res["checks"] if c["name"] == "task-edge:#12" and c["status"] == "fail"]
        self.assertTrue(task_edge_fails)
        self.assertIn("태스크 #13 가 구현 이슈 밖의 #40 와 blocking 으로 이어져 있다", task_edge_fails[0]["detail"])

    def test_11_sub_issue_edge_within_parent(self):
        # 12 의 하위 이슈 13 -> 14 (14 는 12 의 하위 이슈) -> task-edge FAIL 없음
        run = make_tracker(
            issues={12: {}, 13: {"parent": 12}, 14: {"parent": 12}},
            subs={12: [13, 14]},
            edges=[(13, 14)],
        )
        res = batch.plan(url(12), run)
        task_edge_fails = [c for c in res["checks"] if c["name"].startswith("task-edge") and c["status"] == "fail"]
        self.assertEqual(task_edge_fails, [])

    def test_12_cycle(self):
        # 12 -> 14 -> 12 (순환) -> list FAIL
        run = make_tracker(issues={12: {}, 14: {}}, edges=[(12, 14), (14, 12)])
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        list_fails = [c for c in res["checks"] if c["name"] == "list" and c["status"] == "fail"]
        self.assertTrue(list_fails)
        self.assertIn("blocking 순환:", list_fails[0]["detail"])

    def test_13_start_issue_is_sub_issue(self):
        # 시작 이슈가 하위 이슈 -> start FAIL
        run = make_tracker(issues={13: {"parent": 12}})
        res = batch.plan(url(13), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        self.assertEqual(res["order"], [])
        start_fails = [c for c in res["checks"] if c["name"] == "start" and c["status"] == "fail"]
        self.assertTrue(start_fails)

    def test_14_single_closed_issue(self):
        # 12(닫힘) 혼자 -> list FAIL 「열린 구현 이슈가 없다」
        run = make_tracker(issues={12: {"state": "closed"}})
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        self.assertEqual(res["order"], [])
        list_fails = [c for c in res["checks"] if c["name"] == "list" and c["status"] == "fail"]
        self.assertTrue(list_fails)
        self.assertEqual(list_fails[0]["detail"], "열린 구현 이슈가 없다")

    def test_15_before_merge_todo(self):
        # 2 + 14 의 머지 전: 에 1개 -> before-merge:#14 FAIL, 12, 15 도 검사됨
        body_with_todo = TASK_GOOD + "\n## 사람이 할 일\n\n- 머지 전:\n  - 수동 DB 마이그레이션\n- 머지 뒤: 없음\n"
        run = make_tracker(
            issues={12: {}, 14: {"body": body_with_todo}, 15: {}},
            edges=[(12, 14), (14, 15)],
        )
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        bm_fails = [c for c in res["checks"] if c["name"] == "before-merge:#14" and c["status"] == "fail"]
        self.assertTrue(bm_fails)
        self.assertIn("`머지 전:` 에 할 일 1개", bm_fails[0]["detail"])
        # 12 와 15도 검사되었는지 확인
        names = {c["name"] for c in res["checks"]}
        self.assertTrue(any(n.startswith("#12 ") for n in names))
        self.assertTrue(any(n.startswith("#15 ") for n in names))

    def test_16_template_problem(self):
        # 2 + 15 의 본문에 템플릿 필수 절이 없음 -> #15 template:I-15 FAIL, 12, 14 도 검사됨
        body_no_template = "## 배경\n\n내용만 있음\n"
        run = make_tracker(
            issues={12: {}, 14: {}, 15: {"body": body_no_template}},
            edges=[(12, 14), (14, 15)],
        )
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        tpl_fails = [c for c in res["checks"] if c["name"] == "#15 template:I-15" and c["status"] == "fail"]
        self.assertTrue(tpl_fails)
        names = {c["name"] for c in res["checks"]}
        self.assertTrue(any(n.startswith("#12 ") for n in names))
        self.assertTrue(any(n.startswith("#14 ") for n in names))

    def test_17_read_failure(self):
        # 2 + 14 를 읽지 못함(gh 실패) -> read:#14 FAIL
        run = make_tracker(
            issues={12: {}, 14: {}, 15: {}},
            edges=[(12, 14), (14, 15)],
            fail_fetch={14},
        )
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        read_fails = [c for c in res["checks"] if c["name"] == "read:#14" and c["status"] == "fail"]
        self.assertTrue(read_fails)

    def test_18_local_markdown_is_issue_error(self):
        # 시작 참조가 local-markdown 경로 -> IssueError
        with self.assertRaises(issue.IssueError):
            batch.plan(".scratch/ante/issues/03-hand-posts-ante.md", lambda argv: (0, ""))

    def test_sub_issue_dependency_failure_is_read_fail(self):
        # 하위 태스크 #13 의 의존성 API 실패 시 read:#13 FAIL
        run = make_tracker(
            issues={12: {}, 13: {"parent": 12}},
            subs={12: [13]},
            fail_dep={13},
        )
        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        fails = [c for c in res["checks"] if c["name"] == "read:#13" and c["status"] == "fail"]
        self.assertTrue(fails)
        self.assertIn("의존 API", fails[0]["detail"])

    def test_sub_issue_dependency_invalid_json_is_read_fail(self):
        base_run = make_tracker(
            issues={12: {}, 13: {"parent": 12}},
            subs={12: [13]},
        )

        def run(argv):
            path = next((a for a in argv if a.startswith("repos/")), "")
            if "issues/13/dependencies/" in path:
                return 0, "NOT_JSON"
            return base_run(argv)

        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        fails = [c for c in res["checks"] if c["name"] == "read:#13" and c["status"] == "fail"]
        self.assertTrue(fails)
        self.assertIn("JSON", fails[0]["detail"])

    def test_sub_issues_api_failure_is_read_fail(self):
        base_run = make_tracker(issues={12: {}})

        def run(argv):
            path = next((a for a in argv if a.startswith("repos/")), "")
            if "issues/12/sub_issues" in path:
                return 1, ""
            return base_run(argv)

        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        fails = [c for c in res["checks"] if c["name"] == "read:#12" and c["status"] == "fail"]
        self.assertTrue(fails)

    def test_parse_paginated_helper(self):
        self.assertEqual(batch._parse_paginated(""), [])
        self.assertEqual(batch._parse_paginated("   "), [])
        self.assertEqual(batch._parse_paginated('[{"a": 1}]'), [{"a": 1}])
        self.assertEqual(
            batch._parse_paginated('[{"a": 1}][{"b": 2}]'),
            [{"a": 1}, {"b": 2}],
        )
        self.assertEqual(
            batch._parse_paginated('[{"a": 1}]\n\n[{"b": 2}]\n'),
            [{"a": 1}, {"b": 2}],
        )
        with self.assertRaises(ValueError):
            batch._parse_paginated("[{invalid")

    def test_paginated_dependencies_are_parsed_and_followed(self):
        # 12 의 blocking 이 여러 페이지로 분할 출력되어도 모든 이웃(14, 15)을 찾는다
        base_run = make_tracker(issues={12: {}, 14: {}, 15: {}}, edges=[(12, 14), (12, 15)])

        def run(argv):
            path = next((a for a in argv if a.startswith("repos/")), "")
            if "issues/12/dependencies/blocking" in path:
                page1 = json.dumps([{
                    "number": 14,
                    "state": "open",
                    "html_url": url(14),
                    "repository_url": "https://api.github.com/repos/hdmun/poker-server",
                }])
                page2 = json.dumps([{
                    "number": 15,
                    "state": "open",
                    "html_url": url(15),
                    "repository_url": "https://api.github.com/repos/hdmun/poker-server",
                }])
                return 0, page1 + "\n" + page2
            return base_run(argv)

        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 0)
        self.assertEqual([x["number"] for x in res["order"]], [12, 14, 15])

    def test_sub_issue_paginated_dependencies_detect_task_edge(self):
        # 하위 이슈 #13 의 blocking 이 여러 페이지일 때 뒤 페이지의 외부 이슈 #40 도 탐지한다
        base_run = make_tracker(
            issues={12: {}, 13: {"parent": 12}, 14: {"parent": 12}, 40: {}},
            subs={12: [13, 14]},
        )

        def run(argv):
            path = next((a for a in argv if a.startswith("repos/")), "")
            if "issues/13/dependencies/blocking" in path:
                page1 = json.dumps([{
                    "number": 14,
                    "state": "open",
                    "html_url": url(14),
                    "repository_url": "https://api.github.com/repos/hdmun/poker-server",
                }])
                page2 = json.dumps([{
                    "number": 40,
                    "state": "open",
                    "html_url": url(40),
                    "repository_url": "https://api.github.com/repos/hdmun/poker-server",
                }])
                return 0, page1 + page2
            return base_run(argv)

        res = batch.plan(url(12), run)
        self.assertEqual(batch.exit_code(res["checks"]), 1)
        fails = [c for c in res["checks"] if c["name"] == "task-edge:#12" and c["status"] == "fail"]
        self.assertTrue(fails)
        self.assertIn("#40", fails[0]["detail"])


class CliIntegration(unittest.TestCase):
    def test_cli_exit_code_0_on_success(self):
        run = make_tracker(issues={12: {}, 14: {}, 15: {}}, edges=[(12, 14), (14, 15)])
        with patch("relay_cli._run", run), patch("sys.stdout", new_callable=io.StringIO) as out:
            rc = relay_cli.main(["batch-plan", "--issue", url(12)])
            self.assertEqual(rc, 0)
            text = out.getvalue()
            self.assertIn("진행 목록: #12 #14 #15", text)
            self.assertIn("기동 줄 필드: / 일괄 진행: #12 #14 #15", text)

    def test_cli_exit_code_1_on_fail(self):
        run = make_tracker(issues={12: {}, 14: {}}, edges=[(12, 14), (14, 12)])
        with patch("relay_cli._run", run), patch("sys.stdout", new_callable=io.StringIO):
            rc = relay_cli.main(["batch-plan", "--issue", url(12)])
            self.assertEqual(rc, 1)

    def test_cli_exit_code_2_on_input_error(self):
        with patch("sys.stderr", new_callable=io.StringIO):
            rc = relay_cli.main(["batch-plan", "--issue", ".scratch/ante/issues/03-slug.md"])
            self.assertEqual(rc, 2)

    def test_cli_json_flag_outputs_single_line_json(self):
        run = make_tracker(issues={12: {}})
        with patch("relay_cli._run", run), patch("sys.stdout", new_callable=io.StringIO) as out:
            rc = relay_cli.main(["batch-plan", "--issue", url(12), "--json"])
            self.assertEqual(rc, 0)
            data = json.loads(out.getvalue().strip())
            self.assertEqual([x["number"] for x in data["order"]], [12])
            self.assertIn("checks", data)
            self.assertEqual(data["field"], "일괄 진행: #12")

    def test_cli_empty_order_output_format(self):
        run = make_tracker(issues={12: {"state": "closed"}})
        with patch("relay_cli._run", run), patch("sys.stdout", new_callable=io.StringIO) as out:
            rc = relay_cli.main(["batch-plan", "--issue", url(12)])
            self.assertEqual(rc, 1)
            text = out.getvalue()
            self.assertIn("진행 목록: 없음", text)
            self.assertNotIn("기동 줄 필드:", text)


if __name__ == "__main__":
    unittest.main()
