# -*- coding: utf-8 -*-
"""문서 정합성 — SKILL.md 가 부르는 relay_cli 서브커맨드가 실제로 있고, 표로 되돌아간 정책이 없는가."""
import re
import unittest

from helpers import PLUGIN_ROOT

import relay_cli

SKILL_DIR = PLUGIN_ROOT / "skills/relay"
SKILL_MD = (SKILL_DIR / "SKILL.md").read_text(encoding="utf-8")
# 절차가 references/ 로 나뉘었으므로 SKILL.md 와 references/*.md 를 이은 텍스트를 검사한다
SKILL = "\n".join(
    p.read_text(encoding="utf-8")
    for p in [SKILL_DIR / "SKILL.md", *sorted((SKILL_DIR / "references").glob("*.md"))]
)


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

    def test_agy_launch_command_matches_code(self):
        # 회귀: 단독 `agy` 로 띄우면 Orca 의 tui-idle 이 통과하지 못한다 (1.3.3: 11/11 실패)
        from relaylib import orca
        self.assertIn("--command '%s'" % orca.AGY_LAUNCH_COMMAND, SKILL)
        self.assertNotRegex(SKILL, r"--command\s+['\"]?agy\b")

    def test_codex_terminal_launch_bypasses_sandbox(self):
        # 회귀: --yolo 없이 직접 띄운 codex 는 샌드박스 안에서 worker_done 보고가 멈춘다 (2026-10-11 실측)
        launches = re.findall(r"--command\s+'(codex[^']*)'", SKILL)
        self.assertTrue(launches)
        for c in launches:
            self.assertIn("--yolo", c.split())
        self.assertNotIn("worker-start 응답의 launch.effective.model", SKILL)

    def test_every_liveness_call_passes_the_screen(self):
        # 회귀: 확인창은 화면에만 보인다(T-007, agentWait null) — 화면 없이 묻는 liveness 는 빈 대기 30분을 쓴다
        calls = re.findall(r"relay_cli\.py\" liveness [^\n]*", SKILL)
        self.assertTrue(calls)
        for c in calls:
            self.assertIn("--screen", c)
            self.assertIn("--empty-waits", c)

    def test_reused_terminal_is_checked_before_worker_start(self):
        self.assertIn("재사용 전에 `tui-idle`부터 통과시킨다", SKILL)
        self.assertIn("header_scrolled_out", SKILL)

    def test_severity_table_not_reintroduced(self):
        self.assertNotIn("| `MINOR`만 있음 |", SKILL)
        self.assertNotIn("| 총 라운드 5회 초과 |", SKILL)


ORCA_COMMAND = re.compile(r"(?<![\w-])orca (orchestration|terminal|worktree|skills|agent|repo|status|open)(?![\w-])")


class OrcaGuideIsTheSource(unittest.TestCase):
    """명령 문법은 Orca 가이드가 정본이다 — relay 문서는 Orca 스킬로 불러 따르고 스냅숏을 두지 않는다 (ADR 0003)."""

    def test_no_orca_command_snapshots(self):
        hits = [line.strip() for line in SKILL.splitlines() if ORCA_COMMAND.search(line)]
        self.assertEqual(hits, [])

    def test_sessions_load_guides_through_orca_skills(self):
        start = (SKILL_DIR / "references" / "start.md").read_text(encoding="utf-8")
        design = (SKILL_DIR / "references" / "design.md").read_text(encoding="utf-8")
        for text in (start, design):
            self.assertIn("Skill 도구", text)
            self.assertIn("`orchestration`", text)
        self.assertIn("`orca-cli`", start)       # 진행 세션은 워크트리·터미널도 다룬다 (Q3)
        self.assertNotIn("`orca-cli`", design)   # 설계 세션은 Run·Task·게이트만 다룬다

    def test_deviations_from_orca_defaults_sit_after_invariants(self):
        # 컴팩션 뒤에도 남게 SKILL.md 앞부분, 불변식 바로 다음에 둔다
        i, j, k = (SKILL_MD.index(h) for h in ("## 불변식", "## Orca 기본과 다른 점", "## 단계 목록"))
        self.assertLess(i, j)
        self.assertLess(j, k)


class SkillSkeleton(unittest.TestCase):
    def test_skill_md_stays_within_500_lines(self):
        # 다시 비대해지는 것을 막는 상한 (분리 성공 기준). 컴팩션 생존은 리뷰에서 사람이 본다
        self.assertLessEqual(len(SKILL_MD.splitlines()), 500)

    def test_invariants_live_in_skill_md_itself(self):
        # 컴팩션 뒤에는 SKILL.md 앞부분만 다시 붙는다 — 불변식은 references 에만 있으면 안 된다
        from relaylib import orca
        for phrase in (orca.AGY_LAUNCH_COMMAND, "--yolo", "자동 머지 금지", "자동 응답 금지", "<base>"):
            self.assertIn(phrase, SKILL_MD)

    def test_every_step_reference_exists_and_is_read_first(self):
        refs = set(re.findall(r"references/([a-z-]+\.md)", SKILL_MD))
        self.assertTrue(refs)
        for r in refs:
            self.assertTrue((SKILL_DIR / "references" / r).exists(), r)
        self.assertIn("Read 한다", SKILL_MD)


if __name__ == "__main__":
    unittest.main()
