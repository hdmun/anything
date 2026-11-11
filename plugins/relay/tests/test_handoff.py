# -*- coding: utf-8 -*-
"""기동 전 검사 — 태스크 수·템플릿 필수 절·작성자 권한·「사람이 할 일」 절 (ADR 0007, 분담 티켓 #22)."""
import json
import pathlib
import tempfile
import unittest

import helpers  # noqa: F401
from relaylib import handoff, issue

PARENT = "https://github.com/hdmun/poker-server/issues/45"

TASK_GOOD = """## 배경

본문

## 변경 대상 파일

- `src/hand.rs` — 수정

## 인수 조건

- [ ] Ante 를 받는다
- [ ] 게이트 명령: `cargo test --release` — 종료코드로 판정한다
"""

GOOD = TASK_GOOD + """
## 사람이 할 일

- 머지 전: 없음
- 머지 뒤: 없음
"""

PARENT_GOOD = """개요만

## 사람이 할 일

- 머지 전: 없음
- 머지 뒤: 없음
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


class HumanTodo(unittest.TestCase):
    def test_case_01_no_section(self):
        todo, probs = handoff.human_todo("## 배경\n\n본문\n")
        self.assertIsNone(todo)
        self.assertEqual(probs, ["「사람이 할 일」 절이 없다"])

    def test_case_02_both_none(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n- 머지 뒤: 없음\n"
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": []})

    def test_case_03_same_line_value(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n- 머지 뒤: NAS 에 설치\n"
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": ["NAS 에 설치"]})

    def test_case_04_sub_bullets_with_checkbox(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n- 머지 뒤:\n  - [ ] NAS 에 설치\n  - [x] 실제 접속으로 알림을 본다\n"
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": ["NAS 에 설치", "실제 접속으로 알림을 본다"]})

    def test_case_05_sub_bullets_with_deeper_numbered_list(self):
        body = """## 사람이 할 일

- 머지 전: 없음
- 머지 뒤:
  - [ ] NAS 에 설치
  - [ ] 실제 접속으로 알림을 본다
    1. 알림이 온다
    2. 시각이 맞다
"""
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": ["NAS 에 설치", "실제 접속으로 알림을 본다"]})

    def test_case_06_same_line_value_and_sub_bullets(self):
        body = """## 사람이 할 일

- 머지 전: 없음
- 머지 뒤: 아래 둘
  - [ ] NAS 에 설치
  - [ ] 알림 확인
"""
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": ["아래 둘", "NAS 에 설치", "알림 확인"]})

    def test_case_07_no_bullets(self):
        body = "## 사람이 할 일\n\n머지 전: 없음\n머지 뒤: 없음\n"
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": []})

    def test_case_08_star_bullets(self):
        body = "## 사람이 할 일\n\n* 머지 전: 없음\n* 머지 뒤: 없음\n"
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": []})

    def test_case_09_no_value_and_no_sub_items(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n- 머지 뒤:\n\n다음 절\n"
        todo, probs = handoff.human_todo(body)
        self.assertIsNone(todo)
        self.assertEqual(probs, ["`머지 뒤:` 에 값이 없다"])

    def test_case_10_same_line_placeholder(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n- 머지 뒤: <할 일>\n"
        todo, probs = handoff.human_todo(body)
        self.assertIsNone(todo)
        self.assertEqual(probs, ["`머지 뒤:` 에 자리표시(<…>)가 남아 있다"])

    def test_case_11_sub_bullet_placeholder(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n- 머지 뒤:\n  - [ ] <할 일>\n"
        todo, probs = handoff.human_todo(body)
        self.assertIsNone(todo)
        self.assertEqual(probs, ["`머지 뒤:` 에 자리표시(<…>)가 남아 있다"])

    def test_case_12_none_with_sub_bullets(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n  - [ ] 불릿\n- 머지 뒤: 없음\n"
        todo, probs = handoff.human_todo(body)
        self.assertIsNone(todo)
        self.assertEqual(probs, ["`머지 전:` 이 `없음` 인데 하위 항목이 있다"])

    def test_case_13_missing_merge_before(self):
        body = "## 사람이 할 일\n\n- 머지 뒤: 없음\n"
        todo, probs = handoff.human_todo(body)
        self.assertIsNone(todo)
        self.assertEqual(probs, ["`머지 전:` 줄이 없다"])

    def test_case_14_two_merge_after_lines(self):
        body = "## 사람이 할 일\n\n- 머지 전: 없음\n- 머지 뒤: 없음\n- 머지 뒤: 없음\n"
        todo, probs = handoff.human_todo(body)
        self.assertIsNone(todo)
        self.assertEqual(probs, ["`머지 뒤:` 줄이 2개다"])

    def test_case_15_merge_before_inside_html_comment(self):
        body = "## 사람이 할 일\n\n<!-- - 머지 전: 없음 -->\n- 머지 뒤: 없음\n"
        todo, probs = handoff.human_todo(body)
        self.assertIsNone(todo)
        self.assertEqual(probs, ["`머지 전:` 줄이 없다"])

    def test_case_16_explanatory_sentences_ignored(self):
        body = """## 사람이 할 일

구현자·리뷰어는 이 절의 일을 하지 않는다.

- 머지 전: 없음
- 머지 뒤: 없음

추가 안내 문장.
"""
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": []})

    def test_case_17_crlf_line_endings(self):
        body = "## 사람이 할 일\r\n\r\n- 머지 전: 없음\r\n- 머지 뒤: 없음\r\n"
        todo, probs = handoff.human_todo(body)
        self.assertEqual(probs, [])
        self.assertEqual(todo, {"before": [], "after": []})


class Check(unittest.TestCase):
    def test_issue_without_sub_issues_is_one_task(self):
        r = handoff.check(PARENT, tracker({45: (GOOD, "OWNER")}))
        self.assertEqual(r["tasks"], [{"task": "I-45", "url": url(45), "title": "이슈 45"}])
        self.assertEqual(status(r), {"tasks": "ok", "template:I-45": "ok", "author:I-45": "ok", "human:I-45": "ok"})
        self.assertEqual(handoff.exit_code(r["checks"]), 0)
        self.assertEqual(r["human"], {"url": url(45), "before": [], "after": []})

    def test_sub_issues_are_tasks_and_parent_template_is_not_checked(self):
        run = tracker({45: (PARENT_GOOD, "OWNER"), 46: (TASK_GOOD, "OWNER"), 47: (TASK_GOOD, "MEMBER")}, subs=[46, 47])
        r = handoff.check(PARENT, run)
        self.assertEqual([t["task"] for t in r["tasks"]], ["I-46", "I-47"])
        self.assertNotIn("template:I-45", status(r))
        self.assertEqual(status(r)["author:I-45"], "ok")
        self.assertEqual(status(r)["human:I-45"], "ok")
        self.assertEqual(handoff.exit_code(r["checks"]), 0)

    def test_all_failures_are_collected(self):
        # 실패를 모아 한 번에 보고한다 — 첫 실패에서 멈추지 않는다
        issues = {45: ("", "NONE")}
        issues.update({n: ("## 배경\n", "CONTRIBUTOR") for n in range(46, 52)})
        r = handoff.check(PARENT, tracker(issues, subs=list(range(46, 52))))
        s = status(r)
        self.assertEqual(s["tasks"], "fail")
        self.assertEqual(s["author:I-45"], "fail")
        self.assertEqual(s["human:I-45"], "fail")
        self.assertEqual(sum(1 for k, v in s.items() if k.startswith("template:") and v == "fail"), 6)
        self.assertEqual(sum(1 for k, v in s.items() if k.startswith("author:I-4") and k != "author:I-45" and v == "fail"), 4)
        self.assertEqual(handoff.exit_code(r["checks"]), 1)

    def test_five_tasks_is_the_limit(self):
        issues = {45: (PARENT_GOOD, "OWNER")}
        issues.update({n: (TASK_GOOD, "OWNER") for n in range(46, 51)})
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
        self.assertEqual(status(r), {"tasks": "ok", "template:I-ante-03": "ok", "human:I-ante-03": "ok"})

    def test_check_single_issue_without_human_todo(self):
        r = handoff.check(PARENT, tracker({45: (TASK_GOOD, "OWNER")}))
        self.assertEqual(status(r)["human:I-45"], "fail")
        self.assertIsNone(r["human"])
        self.assertEqual(handoff.exit_code(r["checks"]), 1)

    def test_check_sub_issues_parent_missing_human(self):
        run = tracker({45: ("개요만", "OWNER"), 46: (TASK_GOOD, "OWNER")}, subs=[46])
        r = handoff.check(PARENT, run)
        self.assertEqual(status(r)["human:I-45"], "fail")
        self.assertIsNone(r["human"])
        self.assertEqual(handoff.exit_code(r["checks"]), 1)

    def test_check_sub_issues_with_misplaced_human_section(self):
        run = tracker({45: (PARENT_GOOD, "OWNER"), 46: (GOOD, "OWNER")}, subs=[46])
        r = handoff.check(PARENT, run)
        self.assertEqual(status(r)["human:I-45"], "ok")
        self.assertEqual(status(r)["human-misplaced:I-46"], "fail")
        c = next(chk for chk in r["checks"] if chk["name"] == "human-misplaced:I-46")
        self.assertEqual(c["detail"], "하위 이슈에 「사람이 할 일」 절이 있다")
        self.assertEqual(c["fix"], "「사람이 할 일」 절을 부모 이슈로 옮긴다")
        self.assertEqual(handoff.exit_code(r["checks"]), 1)

    def test_check_human_runs_even_if_other_checks_fail(self):
        # 다른 검사(tasks, template, author)가 실패해도 human:* 검사는 돈다
        issues = {45: ("", "NONE")}
        issues.update({n: (TASK_GOOD, "OWNER") for n in range(46, 53)})  # >5 tasks, tasks fail
        r = handoff.check(PARENT, tracker(issues, subs=list(range(46, 53))))
        s = status(r)
        self.assertEqual(s["tasks"], "fail")
        self.assertEqual(s["author:I-45"], "fail")
        self.assertIn("human:I-45", s)
        self.assertEqual(s["human:I-45"], "fail")


if __name__ == "__main__":
    unittest.main()
