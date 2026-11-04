# -*- coding: utf-8 -*-
"""기동 전 검사 — 태스크 수·템플릿 필수 절·작성자 권한 (ADR 0007, 분담 티켓 #22)."""
import json
import pathlib
import tempfile
import unittest

import helpers  # noqa: F401
from relaylib import handoff, issue

PARENT = "https://github.com/hdmun/poker-server/issues/45"

GOOD = """## 배경

본문

## 변경 대상 파일

- `src/hand.rs` — 수정

## 인수 조건

- [ ] Ante 를 받는다
- [ ] 게이트 명령: `cargo test --release` — 종료코드로 판정한다
"""

TEMPLATE_AS_IS = """## 변경 대상 파일

- `path/to/file` — 신규

## 인수 조건

- [ ] 게이트 명령: `<실행 가능한 형태로 명시>` — 종료코드로 판정한다
"""


def url(n):
    return "https://github.com/hdmun/poker-server/issues/%d" % n


def tracker(issues, subs=None, fail=()):
    """issues: {번호: (body, association)}, subs: 부모 번호의 하위 이슈 번호 목록."""
    calls = []

    def run(argv):
        calls.append(argv)
        path = argv[2]
        n = int(path.split("/")[4])
        if n in fail:
            return 1, ""
        if path.endswith("/sub_issues"):
            return 0, json.dumps([{"html_url": url(s)} for s in (subs or [])])
        body, assoc = issues[n]
        return 0, json.dumps({"html_url": url(n), "title": "이슈 %d" % n, "body": body,
                              "updated_at": "2026-11-05T00:00:00Z", "author_association": assoc})
    run.calls = calls
    return run


def status(result):
    return {c["name"]: c["status"] for c in result["checks"]}


class Template(unittest.TestCase):
    def test_good_body_has_no_problems(self):
        self.assertEqual(handoff.template_problems(GOOD), [])

    def test_missing_sections_are_each_reported(self):
        probs = handoff.template_problems("## 배경\n\n본문\n")
        self.assertEqual(len(probs), 2)

    def test_template_placeholders_do_not_count(self):
        probs = handoff.template_problems(TEMPLATE_AS_IS)
        self.assertEqual(len(probs), 2, probs)

    def test_gate_line_inside_html_comment_does_not_count(self):
        body = GOOD.replace("- [ ] 게이트 명령: `cargo test --release`", "<!-- 게이트 명령: `cargo test` -->")
        self.assertEqual(len(handoff.template_problems(body)), 1)

    def test_crlf_body_is_read(self):
        self.assertEqual(handoff.template_problems(GOOD.replace("\n", "\r\n")), [])


class Check(unittest.TestCase):
    def test_issue_without_sub_issues_is_one_task(self):
        r = handoff.check(PARENT, tracker({45: (GOOD, "OWNER")}))
        self.assertEqual(r["tasks"], [{"task": "I-45", "url": url(45), "title": "이슈 45"}])
        self.assertEqual(status(r), {"tasks": "ok", "template:I-45": "ok", "author:I-45": "ok"})
        self.assertEqual(handoff.exit_code(r["checks"]), 0)

    def test_sub_issues_are_tasks_and_parent_template_is_not_checked(self):
        run = tracker({45: ("개요만", "OWNER"), 46: (GOOD, "OWNER"), 47: (GOOD, "MEMBER")}, subs=[46, 47])
        r = handoff.check(PARENT, run)
        self.assertEqual([t["task"] for t in r["tasks"]], ["I-46", "I-47"])
        self.assertNotIn("template:I-45", status(r))
        self.assertEqual(status(r)["author:I-45"], "ok")
        self.assertEqual(handoff.exit_code(r["checks"]), 0)

    def test_all_failures_are_collected(self):
        # 실패를 모아 한 번에 보고한다 — 첫 실패에서 멈추지 않는다
        issues = {45: ("", "NONE")}
        issues.update({n: ("## 배경\n", "CONTRIBUTOR") for n in range(46, 52)})
        r = handoff.check(PARENT, tracker(issues, subs=list(range(46, 52))))
        s = status(r)
        self.assertEqual(s["tasks"], "fail")
        self.assertEqual(s["author:I-45"], "fail")
        self.assertEqual(sum(1 for k, v in s.items() if k.startswith("template:") and v == "fail"), 6)
        self.assertEqual(sum(1 for k, v in s.items() if k.startswith("author:I-4") and k != "author:I-45" and v == "fail"), 4)
        self.assertEqual(handoff.exit_code(r["checks"]), 1)

    def test_five_tasks_is_the_limit(self):
        issues = {45: ("", "OWNER")}
        issues.update({n: (GOOD, "OWNER") for n in range(46, 51)})
        r = handoff.check(PARENT, tracker(issues, subs=list(range(46, 51))))
        self.assertEqual(status(r)["tasks"], "ok")

    def test_unreadable_issue_is_input_error(self):
        with self.assertRaises(issue.IssueError):
            handoff.check(PARENT, tracker({}, fail=(45,)))

    def test_local_markdown_is_one_task_without_author_check(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / ".scratch" / "ante" / "issues" / "3-hand.md"
            p.parent.mkdir(parents=True)
            p.write_text("# Hand 가 Ante 를 받는다\n\n" + GOOD, encoding="utf-8")
            r = handoff.check(str(p), lambda argv: (1, ""))
        self.assertEqual(status(r), {"tasks": "ok", "template:I-ante-03": "ok"})


if __name__ == "__main__":
    unittest.main()
