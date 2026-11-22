# -*- coding: utf-8 -*-
"""구현 이슈 읽기와 spec 스냅숏 (ADR 0006·0007)."""
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

from helpers import SCRIPTS
from relaylib import issue

URL = "https://github.com/hdmun/poker-server/issues/45"


def gh(association="OWNER", body="## 배경\r\n\r\n본문", rc=0):
    calls = []

    def run(argv):
        calls.append(argv)
        return rc, json.dumps({"html_url": URL, "title": "Hand 가 Ante 를 받는다", "body": body,
                               "updated_at": "2026-11-04T01:02:03Z", "author_association": association})
    run.calls = calls
    return run


class Parse(unittest.TestCase):
    def test_github_url_gives_issue_number_id(self):
        ref = issue.parse(URL)
        self.assertEqual((ref["kind"], ref["owner"], ref["repo"], ref["number"]), ("github", "hdmun", "poker-server", 45))
        self.assertEqual(issue.task_id(ref), "I-45")

    def test_local_markdown_id_has_feature_and_two_digits(self):
        ref = issue.parse(".scratch/ante/issues/3-hand-posts-ante.md")
        self.assertEqual(issue.task_id(ref), "I-ante-03")

    def test_unknown_ref_is_input_error(self):
        for bad in ("#45", "https://github.com/hdmun/poker-server/pull/45", "T-043"):
            with self.assertRaises(issue.IssueError):
                issue.parse(bad)


class Snapshot(unittest.TestCase):
    def test_writes_body_with_header_and_reads_only_the_issue(self):
        run = gh()
        with tempfile.TemporaryDirectory() as d:
            got = issue.snapshot(URL, d, "ante", run)
            self.assertEqual(got, {"action": "commit", "task": "I-45", "path": ".relay/specs/I-45-ante.md",
                                   "updatedAt": "2026-11-04T01:02:03Z"})
            text = (pathlib.Path(d) / got["path"]).read_bytes().decode("utf-8")
        self.assertIn("> 이슈: %s\n" % URL, text)
        self.assertIn("> updatedAt: 2026-11-04T01:02:03Z\n", text)
        self.assertIn("# Hand 가 Ante 를 받는다\n\n## 배경\n\n본문\n", text)
        self.assertNotIn("\r", text)
        # 코멘트는 읽지 않는다 — 이슈 본문 하나만 요청한다
        self.assertEqual(run.calls, [["gh", "api", "repos/hdmun/poker-server/issues/45"]])

    def test_untrusted_author_stops_without_writing(self):
        with tempfile.TemporaryDirectory() as d:
            got = issue.snapshot(URL, d, "ante", gh(association="CONTRIBUTOR"))
            self.assertEqual((got["action"], got["reason"]), ("human", "author_not_trusted"))
            self.assertFalse((pathlib.Path(d) / ".relay").exists())

    def test_member_and_collaborator_are_trusted(self):
        for a in ("MEMBER", "COLLABORATOR"):
            with tempfile.TemporaryDirectory() as d:
                self.assertEqual(issue.snapshot(URL, d, "ante", gh(association=a))["action"], "commit")

    def test_tracker_failure_is_input_error(self):
        with tempfile.TemporaryDirectory() as d, self.assertRaises(issue.IssueError):
            issue.snapshot(URL, d, "ante", gh(rc=1))

    def test_slug_must_be_ascii_kebab(self):
        with tempfile.TemporaryDirectory() as d, self.assertRaises(issue.IssueError):
            issue.snapshot(URL, d, "앤티", gh())

    def _existing(self, d, *names):
        specs = pathlib.Path(d) / ".relay" / "specs"
        specs.mkdir(parents=True, exist_ok=True)
        for n in names:
            (specs / n).write_text("old\n", encoding="utf-8")
        return specs

    def test_existing_snapshot_slug_is_reused(self):
        with tempfile.TemporaryDirectory() as d:
            specs = self._existing(d, "I-45-ante.md", "I-4-other.md", "I-450-x.md")
            got = issue.snapshot(URL, d, "hand-ante", gh())
            self.assertEqual((got["path"], got["slug_reused"]), (".relay/specs/I-45-ante.md", "ante"))
            self.assertIn("# Hand 가 Ante 를 받는다", (specs / "I-45-ante.md").read_text(encoding="utf-8"))
            self.assertFalse((specs / "I-45-hand-ante.md").exists())

    def test_same_slug_has_no_slug_reused(self):
        with tempfile.TemporaryDirectory() as d:
            self._existing(d, "I-45-ante.md")
            got = issue.snapshot(URL, d, "ante", gh())
        self.assertEqual(got["path"], ".relay/specs/I-45-ante.md")
        self.assertNotIn("slug_reused", got)

    def test_no_snapshot_uses_given_slug(self):
        with tempfile.TemporaryDirectory() as d:
            self._existing(d, "I-4-other.md")
            got = issue.snapshot(URL, d, "ante", gh())
        self.assertEqual(got["path"], ".relay/specs/I-45-ante.md")
        self.assertNotIn("slug_reused", got)

    def test_two_snapshots_is_input_error(self):
        with tempfile.TemporaryDirectory() as d:
            self._existing(d, "I-45-ante.md", "I-45-hand-ante.md")
            with self.assertRaises(issue.IssueError) as cm:
                issue.snapshot(URL, d, "ante", gh())
        self.assertIn("I-45 의 스냅숏이 여럿이다: I-45-ante.md, I-45-hand-ante.md", str(cm.exception))

    def test_malformed_snapshot_name_is_input_error(self):
        with tempfile.TemporaryDirectory() as d:
            self._existing(d, "I-45-Ante_X.md")
            with self.assertRaises(issue.IssueError):
                issue.snapshot(URL, d, "ante", gh())

    def test_two_snapshots_cli_exits_2(self):
        with tempfile.TemporaryDirectory() as d:
            self._existing(d, "I-ante-03-a.md", "I-ante-03-b.md")
            src = pathlib.Path(d) / ".scratch" / "ante" / "issues" / "03-hand-posts-ante.md"
            src.parent.mkdir(parents=True)
            src.write_text("# 제목\n\n본문\n", encoding="utf-8")
            r = subprocess.run([sys.executable, str(SCRIPTS / "relay_cli.py"), "snapshot", "--issue", str(src),
                                "--worktree", d, "--slug", "a"], capture_output=True)
        self.assertEqual(r.returncode, 2)
        self.assertIn("스냅숏이 여럿이다", r.stderr.decode("utf-8"))

    def test_local_markdown_skips_author_check(self):
        with tempfile.TemporaryDirectory() as d:
            src = pathlib.Path(d) / ".scratch" / "ante" / "issues" / "03-hand-posts-ante.md"
            src.parent.mkdir(parents=True)
            src.write_text("# Hand 가 Ante 를 받는다\n\n## 배경\n본문\n", encoding="utf-8")
            got = issue.snapshot(str(src), d, "hand-posts-ante", lambda argv: (1, ""))
            self.assertEqual((got["action"], got["task"]), ("commit", "I-ante-03"))
            text = (pathlib.Path(d) / got["path"]).read_text(encoding="utf-8")
        self.assertIn("# Hand 가 Ante 를 받는다\n\n## 배경\n본문\n", text)


class Fetch(unittest.TestCase):
    def test_github_fetches_state_and_parent(self):
        ref = issue.parse(URL)

        def run_open(argv):
            return 0, json.dumps({
                "html_url": URL,
                "title": "Title",
                "body": "Body",
                "updated_at": "2026-11-04T01:02:03Z",
                "author_association": "OWNER",
                "state": "open",
                "parent_issue_url": None,
            })

        got = issue.fetch(ref, run_open)
        self.assertEqual(got["state"], "open")
        self.assertIsNone(got["parent"])

        def run_closed_with_parent(argv):
            return 0, json.dumps({
                "html_url": URL,
                "title": "Title",
                "body": "Body",
                "updated_at": "2026-11-04T01:02:03Z",
                "author_association": "OWNER",
                "state": "closed",
                "parent_issue_url": "https://api.github.com/repos/hdmun/poker-server/issues/42",
            })

        got2 = issue.fetch(ref, run_closed_with_parent)
        self.assertEqual(got2["state"], "closed")
        self.assertEqual(got2["parent"], 42)

    def test_local_markdown_returns_open_and_no_parent(self):
        with tempfile.TemporaryDirectory() as d:
            src = pathlib.Path(d) / ".scratch" / "ante" / "issues" / "03-hand-posts-ante.md"
            src.parent.mkdir(parents=True)
            src.write_text("# Hand 가 Ante 를 받는다\n\n## 배경\n본문\n", encoding="utf-8")
            ref = issue.parse(str(src))
            got = issue.fetch(ref, lambda argv: (1, ""))
            self.assertEqual(got["state"], "open")
            self.assertIsNone(got["parent"])


class SnapshotBody(unittest.TestCase):
    def test_roundtrip_render_returns_original_body(self):
        x = {
            "url": URL,
            "title": "제목",
            "body": "## 배경\n\n본문 내용\n- 항목 1\n- 항목 2",
            "updated_at": "2026-11-04T01:02:03Z",
        }
        text = issue.render(x)
        self.assertEqual(issue.snapshot_body(text), x["body"])

    def test_empty_body_render_returns_empty_string(self):
        x = {
            "url": URL,
            "title": "제목",
            "body": "",
            "updated_at": "2026-11-04T01:02:03Z",
        }
        text = issue.render(x)
        self.assertEqual(issue.snapshot_body(text), "")

    def test_body_with_hash_heading_preserves_hashes_in_body(self):
        x = {
            "url": URL,
            "title": "제목",
            "body": "## 배경\n\n# 하위 섹션 1\n\n내용\n# 하위 섹션 2",
            "updated_at": "2026-11-04T01:02:03Z",
        }
        text = issue.render(x)
        self.assertEqual(issue.snapshot_body(text), x["body"])

    def test_missing_header_returns_none(self):
        text = "# 제목\n\n## 배경\n\n본문"
        self.assertIsNone(issue.snapshot_body(text))

    def test_crlf_returns_same_as_lf(self):
        x = {
            "url": URL,
            "title": "제목",
            "body": "## 배경\n\n본문",
            "updated_at": "2026-11-04T01:02:03Z",
        }
        lf_text = issue.render(x)
        crlf_text = lf_text.replace("\n", "\r\n")
        self.assertEqual(issue.snapshot_body(crlf_text), issue.snapshot_body(lf_text))

    def test_invalid_formats_return_none(self):
        self.assertIsNone(issue.snapshot_body(None))
        self.assertIsNone(issue.snapshot_body(""))
        self.assertIsNone(issue.snapshot_body("> 머리말만 있음\n> 이슈: ...\n"))
        self.assertIsNone(issue.snapshot_body("일반 텍스트\n# 제목\n\n본문"))
        self.assertIsNone(issue.snapshot_body("> 머리말\n\n# 제목\n빈줄없이본문"))


if __name__ == "__main__":
    unittest.main()
