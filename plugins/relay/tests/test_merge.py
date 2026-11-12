# -*- coding: utf-8 -*-
"""merge-check·batch-report 단위 테스트 (ADR 0006·0007, I-78)."""
import io
import json
import pathlib
import tempfile
import unittest
from unittest.mock import patch

import helpers  # noqa: F401
import relay_cli
from relaylib import issue, merge

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

PARENT_GOOD = """개요

## 사람이 할 일

- 머지 전: 없음
- 머지 뒤: 없음
"""


def url(n):
    return "https://github.com/hdmun/poker-server/issues/%d" % n


def make_runner(issues=None, subs=None, prs=None, fail_fetch=()):
    issues = issues or {}
    subs = subs or {}
    prs = prs or {}

    calls = []

    def run(argv):
        calls.append(argv)
        # gh issue view <url> --json closedByPullRequestsReferences
        if len(argv) >= 4 and argv[0] == "gh" and argv[1] == "issue" and argv[2] == "view":
            target_url = argv[3]
            try:
                num = int(target_url.rstrip("/").split("/")[-1])
            except ValueError:
                return 1, ""
            if num in fail_fetch:
                return 1, ""
            ref_list = prs.get(num, [])
            return 0, json.dumps({"closedByPullRequestsReferences": ref_list})

        # gh api repos/owner/repo/issues/<num>...
        path = None
        for a in argv:
            if a.startswith("repos/"):
                path = a
                break
        if not path:
            return 1, ""

        parts = path.split("/")
        num = int(parts[4])
        if num in fail_fetch:
            return 1, ""

        if path.endswith("/sub_issues"):
            s_list = subs.get(num, [])
            return 0, json.dumps([{"html_url": url(s)} for s in s_list])

        data = issues.get(num, {})
        body = data.get("body", GOOD_BODY)
        updated_at = data.get("updated_at", "2026-11-04T01:02:03Z")
        assoc = data.get("author_association", "OWNER")
        return 0, json.dumps({
            "html_url": url(num),
            "title": "이슈 %d" % num,
            "body": body,
            "updated_at": updated_at,
            "author_association": assoc,
            "state": "open",
        })

    run.calls = calls
    return run


def make_spec(worktree, tid, slug, body, updated_at="2026-11-04T01:02:03Z"):
    specs_dir = pathlib.Path(worktree) / ".ai" / "specs"
    specs_dir.mkdir(parents=True, exist_ok=True)
    num = int(tid.replace("I-", "")) if tid.startswith("I-") else 45
    item = {
        "url": url(num),
        "title": "이슈 %d" % num,
        "body": body,
        "updated_at": updated_at,
    }
    spec_path = specs_dir / ("%s-%s.md" % (tid, slug))
    spec_path.write_text(issue.render(item), encoding="utf-8", newline="\n")
    return spec_path


class TestParseList(unittest.TestCase):
    def test_space_separated_hashes(self):
        self.assertEqual(merge.parse_list("#12 #14"), [12, 14])

    def test_comma_separated(self):
        self.assertEqual(merge.parse_list("12,14"), [12, 14])

    def test_hash_comma_separated(self):
        self.assertEqual(merge.parse_list("#12, #14"), [12, 14])

    def test_three_items(self):
        self.assertEqual(merge.parse_list("#12 #14 #15"), [12, 14, 15])
        self.assertEqual(merge.parse_list("12,14,15"), [12, 14, 15])

    def test_field_prefix_supported(self):
        self.assertEqual(merge.parse_list("일괄 진행: #12 #14"), [12, 14])

    def test_empty_string_raises_value_error(self):
        with self.assertRaises(ValueError):
            merge.parse_list("")
        with self.assertRaises(ValueError):
            merge.parse_list("   ")
        with self.assertRaises(ValueError):
            merge.parse_list("일괄 진행:")

    def test_invalid_tokens_raise_value_error(self):
        for bad in ("#12 abc", "abc", "#", "-12", "12a"):
            with self.assertRaises(ValueError):
                merge.parse_list(bad)


class TestMergeCheck(unittest.TestCase):
    def test_no_sub_issues_all_ok(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", GOOD_BODY)
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        statuses = {c["name"]: c["status"] for c in res["checks"]}
        self.assertEqual(statuses, {
            "done:I-45": "ok",
            "snapshot:I-45": "ok",
            "before-merge:I-45": "ok",
        })
        self.assertEqual(merge.exit_code(res["checks"]), 0)

    def test_two_sub_issues_one_missing_relay_done(self):
        runner = make_runner(
            issues={45: {"body": PARENT_GOOD}, 46: {"body": GOOD_BODY}, 47: {"body": GOOD_BODY}},
            subs={45: [46, 47]},
        )
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-46", "sub1", GOOD_BODY)
            make_spec(d, "I-47", "sub2", GOOD_BODY)
            git = lambda wt, *args: "I-46\n"  # I-47 누락
            res = merge.check(url(45), d, runner, git)

        c_map = {c["name"]: (c["status"], c["detail"]) for c in res["checks"]}
        self.assertEqual(c_map["done:I-46"][0], "ok")
        self.assertEqual(c_map["done:I-47"], ("fail", "Relay-Done 이 없다"))
        self.assertEqual(c_map["snapshot:I-46"][0], "ok")
        self.assertEqual(c_map["snapshot:I-47"][0], "ok")
        self.assertEqual(c_map["before-merge:I-45"][0], "ok")
        self.assertEqual(merge.exit_code(res["checks"]), 1)

    def test_snapshot_file_missing_fails(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            # 스냅숏 파일 생성 안 함
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "snapshot:I-45")
        self.assertEqual(c["status"], "fail")
        self.assertEqual(c["detail"], "스냅숏 파일이 0개다")
        self.assertEqual(merge.exit_code(res["checks"]), 1)

    def test_snapshot_file_multiple_fails(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "first", GOOD_BODY)
            make_spec(d, "I-45", "second", GOOD_BODY)
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "snapshot:I-45")
        self.assertEqual(c["status"], "fail")
        self.assertEqual(c["detail"], "스냅숏 파일이 2개다")
        self.assertEqual(merge.exit_code(res["checks"]), 1)

    def test_snapshot_body_trailing_newline_difference_is_ok(self):
        runner = make_runner({45: {"body": GOOD_BODY + "\n\n"}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", GOOD_BODY)
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "snapshot:I-45")
        self.assertEqual(c["status"], "ok")
        self.assertEqual(merge.exit_code(res["checks"]), 0)

    def test_snapshot_body_one_char_change_fails(self):
        changed_body = GOOD_BODY + "추가된 한 글자"
        runner = make_runner({45: {"body": changed_body}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", GOOD_BODY)
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "snapshot:I-45")
        self.assertEqual(c["status"], "fail")
        self.assertEqual(c["detail"], "태스크 도중 이슈 본문이 바뀌었다 — 반영되지 않은 채 머지하지 않는다")
        self.assertEqual(merge.exit_code(res["checks"]), 1)

    def test_updated_at_change_only_is_ok(self):
        runner = make_runner({45: {"body": GOOD_BODY, "updated_at": "2026-11-10T09:00:00Z"}})
        with tempfile.TemporaryDirectory() as d:
            # 스냅숏은 2026-11-01T00:00:00Z 로 기록됨
            make_spec(d, "I-45", "ante", GOOD_BODY, updated_at="2026-11-01T00:00:00Z")
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "snapshot:I-45")
        self.assertEqual(c["status"], "ok")
        self.assertEqual(merge.exit_code(res["checks"]), 0)

    def test_parent_human_before_merge_has_item_fails(self):
        parent_with_before = """개요

## 사람이 할 일

- 머지 전: 마이그레이션 실행
- 머지 뒤: 없음
"""
        runner = make_runner({45: {"body": parent_with_before}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", parent_with_before)
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "before-merge:I-45")
        self.assertEqual(c["status"], "fail")
        self.assertEqual(c["detail"], "`머지 전:` 에 할 일 1개")
        self.assertEqual(merge.exit_code(res["checks"]), 1)

    def test_multiple_fails_all_reported(self):
        parent_bad = """개요

## 사람이 할 일

- 머지 전: 할 일 1
- 머지 뒤: 없음
"""
        runner = make_runner(
            issues={45: {"body": parent_bad}, 46: {"body": GOOD_BODY + "변경"}},
            subs={45: [46]},
        )
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-46", "sub1", GOOD_BODY)
            git = lambda wt, *args: ""  # Relay-Done 없음
            res = merge.check(url(45), d, runner, git)

        c_map = {c["name"]: c["status"] for c in res["checks"]}
        self.assertEqual(c_map["done:I-46"], "fail")
        self.assertEqual(c_map["snapshot:I-46"], "fail")
        self.assertEqual(c_map["before-merge:I-45"], "fail")
        self.assertEqual(merge.exit_code(res["checks"]), 1)

    def test_invalid_snapshot_format_fails(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            specs_dir = pathlib.Path(d) / ".ai" / "specs"
            specs_dir.mkdir(parents=True, exist_ok=True)
            bad_spec = specs_dir / "I-45-bad.md"
            bad_spec.write_text("머리말 없는 일반 파일\n", encoding="utf-8")
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "snapshot:I-45")
        self.assertEqual(c["status"], "fail")
        self.assertEqual(c["detail"], "스냅숏 형식을 읽지 못했다")

    def test_missing_human_section_fails(self):
        body_no_human = TASK_GOOD
        runner = make_runner({45: {"body": body_no_human}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", body_no_human)
            git = lambda wt, *args: "I-45\n"
            res = merge.check(url(45), d, runner, git)

        c = next(x for x in res["checks"] if x["name"] == "before-merge:I-45")
        self.assertEqual(c["status"], "fail")
        self.assertEqual(c["detail"], "「사람이 할 일」 절을 읽지 못했다")


class TestBatchReport(unittest.TestCase):
    def test_normal_report_generation(self):
        body12 = GOOD_BODY.replace("- 머지 뒤: 없음", "- 머지 뒤:\n  - 항목1\n  - 항목2")
        body14 = GOOD_BODY
        # #15 fetch fail
        runner = make_runner(
            issues={
                12: {"body": body12},
                14: {"body": body14},
            },
            prs={
                12: [{"url": "https://github.com/hdmun/poker-server/pull/101", "number": 101}],
                14: [{"url": "https://github.com/hdmun/poker-server/pull/102", "number": 102}],
                15: [],  # PR 없음
            },
            fail_fetch=(15,),
        )

        res = merge.report(url(15), [12, 14, 15], runner)
        self.assertEqual(res["issues"], [
            {"number": 12, "pr": "https://github.com/hdmun/poker-server/pull/101", "after": 2},
            {"number": 14, "pr": "https://github.com/hdmun/poker-server/pull/102", "after": 0},
            {"number": 15, "pr": None, "after": None},
        ])

        expected_body = (
            "relay 완료 보고 — 일괄 진행 #12 #14 #15\n\n"
            "- #12: https://github.com/hdmun/poker-server/pull/101 · 머지 뒤 할 일 2개\n"
            "- #14: https://github.com/hdmun/poker-server/pull/102 · 머지 뒤 할 일 없음\n"
            "- #15: 머지된 PR 없음 · 머지 뒤 할 일 읽지 못함\n"
        )
        self.assertEqual(res["body"], expected_body)

    def test_empty_prs_reports_no_merged_pr(self):
        runner = make_runner(
            issues={12: {"body": GOOD_BODY}},
            prs={12: []},
        )
        res = merge.report(url(12), [12], runner)
        self.assertIn("- #12: 머지된 PR 없음 · 머지 뒤 할 일 없음\n", res["body"])

    def test_non_github_raises_issue_error(self):
        with self.assertRaises(issue.IssueError):
            merge.report(".scratch/ante/issues/03-hand.md", [12], lambda argv: (0, ""))


class TestCliIntegration(unittest.TestCase):
    def test_merge_check_ok(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", GOOD_BODY)
            with patch("relay_cli._run", runner), patch("relay_cli._git", return_value="I-45\n"):
                out = io.StringIO()
                with patch("sys.stdout", out):
                    rc = relay_cli.main(["merge-check", "--issue", url(45), "--worktree", d])
                self.assertEqual(rc, 0)
                text = out.getvalue()
                self.assertIn("OK   done:I-45", text)
                self.assertIn("OK   snapshot:I-45", text)
                self.assertIn("OK   before-merge:I-45", text)

    def test_merge_check_json_output(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", GOOD_BODY)
            with patch("relay_cli._run", runner), patch("relay_cli._git", return_value="I-45\n"):
                out = io.StringIO()
                with patch("sys.stdout", out):
                    rc = relay_cli.main(["merge-check", "--issue", url(45), "--worktree", d, "--json"])
                self.assertEqual(rc, 0)
                data = json.loads(out.getvalue())
                self.assertIn("checks", data)

    def test_merge_check_fail_exits_1(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            make_spec(d, "I-45", "ante", GOOD_BODY)
            with patch("relay_cli._run", runner), patch("relay_cli._git", return_value=""):  # Relay-Done 없음
                out = io.StringIO()
                with patch("sys.stdout", out):
                    rc = relay_cli.main(["merge-check", "--issue", url(45), "--worktree", d])
                self.assertEqual(rc, 1)

    def test_batch_report_writes_file_and_emits_json(self):
        runner = make_runner(
            issues={12: {"body": GOOD_BODY}},
            prs={12: [{"url": "https://github.com/hdmun/poker-server/pull/1", "number": 1}]},
        )
        with tempfile.TemporaryDirectory() as d:
            out_file = pathlib.Path(d) / "report.md"
            out = io.StringIO()
            with patch("relay_cli._run", runner), patch("sys.stdout", out):
                rc = relay_cli.main(["batch-report", "--issue", url(12), "--list", "#12", "--out", str(out_file)])
            self.assertEqual(rc, 0)
            self.assertTrue(out_file.exists())
            written = out_file.read_text(encoding="utf-8")
            self.assertIn("relay 완료 보고 — 일괄 진행 #12", written)
            emitted = json.loads(out.getvalue())
            self.assertEqual(emitted["action"], "report")
            self.assertEqual(emitted["path"], str(out_file))

    def test_batch_report_invalid_list_exits_2(self):
        err = io.StringIO()
        with patch("sys.stderr", err):
            rc = relay_cli.main(["batch-report", "--issue", url(12), "--list", "#12 abc", "--out", "out.md"])
        self.assertEqual(rc, 2)

    def test_git_failure_exits_2(self):
        runner = make_runner({45: {"body": GOOD_BODY}})
        with tempfile.TemporaryDirectory() as d:
            def bad_git(wt, *args):
                raise relay_cli.InputError("git failed")
            with patch("relay_cli._run", runner), patch("relay_cli._git", bad_git):
                err = io.StringIO()
                with patch("sys.stderr", err):
                    rc = relay_cli.main(["merge-check", "--issue", url(45), "--worktree", d])
                self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main()
