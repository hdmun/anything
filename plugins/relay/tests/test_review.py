# -*- coding: utf-8 -*-
import json
import pathlib
import re
import tempfile
import unittest

from helpers import PLUGIN_ROOT
from relaylib import review


def finding(sev, file="a.go", summary="s", **kw):
    f = {"severity": sev, "file": file, "summary": summary, "repro": "x -> y"}
    if sev == "SPEC_VIOLATION":
        f["specRef"] = "spec 3.1"
    f.update(kw)
    return f


def report(verdict, *findings, task="T-004"):
    return {"taskId": task, "verdict": verdict, "findings": list(findings)}


class Validate(unittest.TestCase):
    def ok(self, r, **kw):
        self.assertEqual(review.validate(r, **kw), [])

    def bad(self, r, needle, **kw):
        errs = review.validate(r, **kw)
        self.assertTrue(any(needle in e for e in errs), errs)

    def test_valid_pass(self):
        self.ok(report("pass"))
        self.ok(report("pass", finding("MINOR")))

    def test_valid_changes_requested(self):
        self.ok(report("changes_requested", finding("MAJOR", line=297)))

    def test_not_an_object(self):
        self.bad([], "객체")

    def test_missing_top_level(self):
        self.bad({"taskId": "T-1", "verdict": "pass"}, "findings")

    def test_extra_top_level(self):
        r = report("pass")
        r["score"] = 3
        self.bad(r, "score")

    def test_bad_verdict(self):
        self.bad(report("approve"), "verdict")

    def test_finding_missing_repro(self):
        f = finding("MAJOR")
        del f["repro"]
        self.bad(report("changes_requested", f), "repro")

    def test_finding_extra_field(self):
        self.bad(report("changes_requested", finding("MAJOR", fix="...")), "fix")

    def test_bad_severity(self):
        self.bad(report("changes_requested", finding("CRITICAL")), "severity")

    def test_line_must_be_integer_not_bool(self):
        self.bad(report("changes_requested", finding("MAJOR", line="42")), "line")
        self.bad(report("changes_requested", finding("MAJOR", line=True)), "line")

    def test_spec_violation_needs_spec_ref(self):
        f = finding("SPEC_VIOLATION")
        del f["specRef"]
        self.bad(report("changes_requested", f), "specRef")

    def test_pass_with_major_is_contradiction(self):
        self.bad(report("pass", finding("MAJOR")), "pass")

    def test_changes_requested_with_only_minor_is_contradiction(self):
        # MINOR 는 수정 대상이 아니므로 changes_requested 를 줄 근거가 없다
        self.bad(report("changes_requested", finding("MINOR")), "changes_requested")
        self.bad(report("changes_requested"), "changes_requested")

    def test_task_id_must_match_file_name(self):
        self.bad(report("pass", task="T-005"), "taskId", expected_task="T-004")
        self.ok(report("pass"), expected_task="T-004")


class SchemaAndTemplateAgree(unittest.TestCase):
    """문서 정합성 — 스키마·리뷰어 템플릿·검증기가 같은 심각도와 필드를 말하는가."""

    def setUp(self):
        self.schema = json.loads((PLUGIN_ROOT / "skills/relay/references/review-schema.json").read_text(encoding="utf-8"))

    def test_severity_enum(self):
        enum = self.schema["$defs"]["finding"]["properties"]["severity"]["enum"]
        self.assertEqual(tuple(enum), review.SEVERITIES)
        tmpl = (PLUGIN_ROOT / "templates/reviewer.md.tmpl").read_text(encoding="utf-8")
        for sev in review.SEVERITIES:
            self.assertIn("| `%s` |" % sev, tmpl)

    def test_fields(self):
        f = self.schema["$defs"]["finding"]
        self.assertEqual(set(f["properties"]), set(review.FINDING_FIELDS))
        self.assertEqual(set(f["required"]), set(review.FINDING_REQUIRED))
        self.assertEqual(set(self.schema["required"]), set(review.TOP_REQUIRED))

    def test_schema_encodes_both_consistency_rules(self):
        conds = [c["if"]["properties"]["verdict"]["const"] for c in self.schema["allOf"]]
        self.assertEqual(sorted(conds), ["changes_requested", "pass"])


class Branch(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.dir = pathlib.Path(self._d.name)

    def tearDown(self):
        self._d.cleanup()

    def put(self, n, r, task="T-004"):
        (self.dir / ("%s.r%d.json" % (task, n))).write_text(json.dumps(r, ensure_ascii=False), encoding="utf-8")

    def decide(self, impl=1, task="T-004"):
        return review.decide(self.dir, task, impl_rounds=impl)

    # (g) 심각도 분기
    def test_pass(self):
        self.put(1, report("pass"))
        self.assertEqual(self.decide()["action"], "success")

    def test_minor_only_pass(self):
        self.put(1, report("pass", finding("MINOR")))
        d = self.decide()
        self.assertEqual(d["action"], "success")

    def test_spec_violation_escalates(self):
        self.put(1, report("changes_requested", finding("SPEC_VIOLATION"), finding("MAJOR")))
        d = self.decide()
        self.assertEqual((d["action"], d["reason"]), ("escalate", "spec_violation"))

    def test_major_opens_fix_round(self):
        self.put(1, report("changes_requested", finding("MAJOR", line=297)))
        d = self.decide()
        self.assertEqual(d["action"], "fix_round")
        self.assertEqual(d["round"], 2)
        self.assertEqual(d["report"], str(self.dir / "T-004.r1.json"))

    def test_invalid_report_asks_rewrite(self):
        self.put(1, report("pass", finding("MAJOR")))
        d = self.decide()
        self.assertEqual(d["action"], "rewrite")
        self.assertTrue(d["errors"])

    def test_no_report(self):
        with self.assertRaises(review.ReviewError):
            self.decide()

    def test_latest_round_wins_numerically(self):
        # r10 이 r9 보다 뒤다 — 문자열 정렬이면 r10 < r2 가 된다
        for n in range(1, 10):
            self.put(n, report("changes_requested", finding("MAJOR", summary="s%d" % n)))
        self.put(10, report("pass"))
        self.assertEqual(self.decide(impl=10)["action"], "success")

    def test_other_tasks_ignored(self):
        self.put(1, report("changes_requested", finding("MAJOR"), task="T-003"), task="T-003")
        self.put(1, report("pass"))
        self.assertEqual(self.decide()["action"], "success")

    # (h) 라운드 판정
    def test_repeated_finding_escalates(self):
        self.put(1, report("changes_requested", finding("MAJOR", file="a.go", summary="불변식 미검증")))
        self.put(2, report("changes_requested", finding("BLOCKER", file="a.go", summary="  불변식  미검증 ")))
        d = self.decide(impl=2)
        self.assertEqual((d["action"], d["reason"]), ("escalate", "repeated_finding"))

    def test_repeated_check_uses_previous_round_only(self):
        self.put(1, report("changes_requested", finding("MAJOR", summary="A")))
        self.put(2, report("changes_requested", finding("MAJOR", summary="B")))
        self.put(3, report("changes_requested", finding("MAJOR", summary="A")))
        d = self.decide(impl=2)
        self.assertNotEqual(d.get("reason"), "repeated_finding")

    def test_repeated_minor_is_fine(self):
        self.put(1, report("pass", finding("MINOR", summary="이름")))
        self.put(2, report("changes_requested", finding("MINOR", summary="이름"), finding("MAJOR", summary="new")))
        self.assertEqual(self.decide(impl=2)["action"], "fix_round")

    def test_total_round_limit_calls_human(self):
        # 구현 3 + 리뷰 3 = 6 > 5
        self.put(1, report("changes_requested", finding("MAJOR", summary="a")))
        self.put(2, report("changes_requested", finding("MAJOR", summary="b")))
        self.put(3, report("changes_requested", finding("MAJOR", summary="c")))
        d = self.decide(impl=3)
        self.assertEqual((d["action"], d["reason"]), ("human", "total_round_limit"))

    def test_review_round_limit_escalates(self):
        for n, s in enumerate("abcd", 1):
            self.put(n, report("changes_requested", finding("MAJOR", summary=s)))
        d = self.decide(impl=1)
        self.assertEqual((d["action"], d["reason"]), ("escalate", "review_round_limit"))

    def test_limits_do_not_block_success(self):
        for n, s in enumerate("abc", 1):
            self.put(n, report("changes_requested", finding("MAJOR", summary=s)))
        self.put(4, report("pass"))
        self.assertEqual(self.decide(impl=4)["action"], "success")

    def test_decision_is_one_json_line(self):
        self.put(1, report("pass"))
        line = json.dumps(self.decide(), ensure_ascii=False)
        self.assertNotIn("\n", line)
        self.assertTrue(re.match(r'^\{"action":', line))


if __name__ == "__main__":
    unittest.main()
