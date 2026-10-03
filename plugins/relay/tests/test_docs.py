# -*- coding: utf-8 -*-
"""문서 정합성 — SKILL.md 가 부르는 relay_cli 서브커맨드가 실제로 있고, 표로 되돌아간 정책이 없는가."""
import re
import unittest

from helpers import PLUGIN_ROOT

import relay_cli

SKILL = (PLUGIN_ROOT / "skills/relay/SKILL.md").read_text(encoding="utf-8")


def _subcommands():
    ap = relay_cli.build_parser()
    for action in ap._actions:
        if getattr(action, "choices", None) and isinstance(action.choices, dict):
            return set(action.choices)
    return set()


class SkillCallsExistingCommands(unittest.TestCase):
    def test_every_relay_cli_call_is_a_real_subcommand(self):
        called = set(re.findall(r"relay_cli\.py\"? ([a-z][a-z-]+)", SKILL))
        self.assertTrue(called, "SKILL.md 에 relay_cli 호출이 하나도 없다")
        self.assertLessEqual(called - {"--help"}, _subcommands())

    def test_no_inline_python_heredoc(self):
        # 정책을 스크립트로 옮긴 뒤 heredoc 이 되살아나면 두 정본이 생긴다 (ADR 0001)
        self.assertNotIn("<<'PY'", SKILL)

    def test_severity_table_not_reintroduced(self):
        self.assertNotIn("| `MINOR`만 있음 |", SKILL)
        self.assertNotIn("| 총 라운드 5회 초과 |", SKILL)


if __name__ == "__main__":
    unittest.main()
