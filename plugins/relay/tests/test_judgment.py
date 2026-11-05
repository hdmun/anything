# -*- coding: utf-8 -*-
"""판정 서브에이전트의 입출력 계약 (ADR 0008, #23)."""
import json
import pathlib
import tempfile
import unittest

from helpers import PLUGIN_ROOT
from test_cli_git import cli
from relaylib import judgment, models, orca

SCHEMA = json.loads((PLUGIN_ROOT / "skills/relay/references/judgment-schema.json").read_text(encoding="utf-8"))


def j(reason="spec_violation", decision="dismiss", **kw):
    d = {"reason": reason, "decision": decision, "rationale": "spec 「시그니처」 절, src/a.rs:12"}
    if decision == "stop":
        d["stop_summary"] = "spec 이 Ante 순서를 정하지 않았다 — 순서를 이슈에 적는다"
    else:
        d["instruction"] = "지적은 spec 범위 밖이다"
    d.update(kw)
    return d


class Validate(unittest.TestCase):
    def test_every_allowed_pair_passes(self):
        for reason, decisions in judgment.DECISIONS.items():
            for d in decisions:
                self.assertEqual(judgment.validate(j(reason, d)), [], (reason, d))

    def test_decision_must_fit_the_reason(self):
        # spec 을 고치는 선택지는 없다 — 판정은 spec 안에서만 (ADR 0008)
        for reason, d in (("spec_violation", "accept"), ("question", "dismiss"), ("repeated_finding", "fix_spec")):
            self.assertTrue(judgment.validate(j(reason, d)), (reason, d))

    def test_stop_needs_summary_and_others_need_instruction(self):
        bad = j(decision="stop")
        del bad["stop_summary"]
        self.assertTrue(judgment.validate(bad))
        bad = j(decision="dismiss")
        del bad["instruction"]
        self.assertTrue(judgment.validate(bad))
        self.assertTrue(judgment.validate(j(decision="dismiss", stop_summary="x")))

    def test_extra_or_empty_fields_fail(self):
        self.assertTrue(judgment.validate(j(extra="x")))
        self.assertTrue(judgment.validate(j(rationale="  ")))
        self.assertTrue(judgment.validate([]))

    def test_reason_must_match_what_was_asked(self):
        self.assertTrue(judgment.validate(j("question", "answer"), reason="spec_violation"))

    def test_schema_lists_the_same_values(self):
        self.assertEqual(SCHEMA["properties"]["reason"]["enum"], list(judgment.DECISIONS))
        decisions = {d for ds in judgment.DECISIONS.values() for d in ds}
        self.assertEqual(set(SCHEMA["properties"]["decision"]["enum"]), decisions)
        self.assertEqual(set(SCHEMA["properties"]), set(judgment.FIELDS))

    def test_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            good, bad = pathlib.Path(d) / "I-4.j1.json", pathlib.Path(d) / "I-4.j2.json"
            good.write_text(json.dumps(j()), encoding="utf-8")
            bad.write_text("{", encoding="utf-8")
            self.assertEqual(cli("judgment", "validate", str(good), "--reason", "spec_violation").returncode, 0)
            self.assertEqual(cli("judgment", "validate", str(bad)).returncode, 1)
            self.assertEqual(cli("judgment", "validate", str(pathlib.Path(d) / "none.json")).returncode, 2)


class JudgeModel(unittest.TestCase):
    def test_default_is_opus_high(self):
        self.assertEqual(orca.judge_model({}), {"action": "launch", "agent": "subagent", "model": "opus",
                                                "effort": "high", "source": "default"})

    def test_non_alias_model_needs_a_human(self):
        d = orca.judge_model(models.parse(json.dumps({"judge": {"model": "claude-opus-5-5"}})))
        self.assertEqual((d["action"], d["reason"]), ("human", "judge_model_invalid"))

    def test_configured_alias_and_effort(self):
        d = orca.judge_model(models.parse(json.dumps({"judge": {"model": "sonnet", "effort": "max"}})))
        self.assertEqual((d["model"], d["effort"], d["source"]), ("sonnet", "max", "relay_models"))


if __name__ == "__main__":
    unittest.main()
