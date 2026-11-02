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

    def test_workers_launch_through_worker_start_agent(self):
        # 기동은 Orca 기본 경로다 (ADR 0003, 트랙 0 에서 agy 7/7·codex 4/4). 터미널 선기동·명령줄 조립이 되살아나지 않게
        for agent in ("claude", "antigravity", "codex"):
            self.assertIn("--agent %s" % agent, SKILL)
        self.assertNotRegex(SKILL, r"--command\s+'")
        for gone in ("$null=1", "--yolo", "tui-idle", "HandleUserInput called"):
            self.assertNotIn(gone, SKILL)

    def test_every_liveness_call_passes_the_screen(self):
        # 회귀: 확인창은 화면에만 보인다(T-007, agentWait null) — 화면 없이 묻는 liveness 는 빈 대기 30분을 쓴다
        calls = re.findall(r"relay_cli\.py\" liveness [^\n]*", SKILL)
        self.assertTrue(calls)
        for c in calls:
            self.assertIn("--screen", c)
            self.assertIn("--empty-waits", c)

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
        self.assertIn("`orca-cli`", start)       # 진행자 워커는 워크트리·터미널도 다룬다 (Q3)
        self.assertNotIn("`orca-cli`", design)   # 설계 세션은 Run·Task·게이트만 다룬다

    def test_deviations_from_orca_defaults_sit_after_invariants(self):
        # 컴팩션 뒤에도 남게 SKILL.md 앞부분, 불변식 바로 다음에 둔다
        i, j, k = (SKILL_MD.index(h) for h in ("## 불변식", "## Orca 기본과 다른 점", "## 단계 목록"))
        self.assertLess(i, j)
        self.assertLess(j, k)


class SessionStructure(unittest.TestCase):
    """설계 세션이 진행자 워커를 감독한다 (ADR 0004)."""

    def test_session_is_classified_by_orca_preamble(self):
        # 판정은 진입 절에 있어야 첫 Read 에서 갈린다 (Q11). 옛 기준(run-use 여부)이 되살아나면 두 기준이 생긴다
        entry = SKILL_MD.split("## 진입 약속과 세션 판정")[1].split("\n## ")[0]
        self.assertIn("preamble", entry)
        self.assertIn("relay 진행자: Run <run_id> / T-NNN", entry)
        self.assertNotIn("run-use로 기존 Run에 들어왔으면", SKILL_MD)

    def test_escalation_goes_through_ask_not_decision_gates(self):
        # decision gate 는 세션 종료를 전제로 한 설계라 폐기했다 (Q12). 진행자는 ask 로 설계 세션에 묻는다
        self.assertNotRegex(SKILL, r"gate-(create|resolve|list)")
        escalation = (SKILL_DIR / "references" / "escalation.md").read_text(encoding="utf-8")
        self.assertIn("같은 메시지 ID로 resume", escalation)    # ask 30분 timeout 뒤 중복 질문을 만들지 않는다


class SkillSkeleton(unittest.TestCase):
    def test_skill_md_stays_within_500_lines(self):
        # 다시 비대해지는 것을 막는 상한 (분리 성공 기준). 컴팩션 생존은 리뷰에서 사람이 본다
        self.assertLessEqual(len(SKILL_MD.splitlines()), 500)

    def test_invariants_live_in_skill_md_itself(self):
        # 컴팩션 뒤에는 SKILL.md 앞부분만 다시 붙는다 — 불변식은 references 에만 있으면 안 된다
        for phrase in ("worker-start --agent", "자동 머지 금지", "자동 응답 금지", "<base>"):
            self.assertIn(phrase, SKILL_MD)

    def test_every_step_reference_exists_and_is_read_first(self):
        refs = set(re.findall(r"references/([a-z-]+\.md)", SKILL_MD))
        self.assertTrue(refs)
        for r in refs:
            self.assertTrue((SKILL_DIR / "references" / r).exists(), r)
        self.assertIn("Read 한다", SKILL_MD)


if __name__ == "__main__":
    unittest.main()
