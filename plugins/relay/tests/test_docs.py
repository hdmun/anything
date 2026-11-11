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
HANDOFF_DIR = PLUGIN_ROOT / "skills/handoff"
HANDOFF_MD = (HANDOFF_DIR / "SKILL.md").read_text(encoding="utf-8")
HANDOFF = "\n".join(
    p.read_text(encoding="utf-8")
    for p in [HANDOFF_DIR / "SKILL.md", *sorted((HANDOFF_DIR / "references").glob("*.md"))]
)
SPEC_DIR = PLUGIN_ROOT / "skills/spec"
SPEC_MD = (SPEC_DIR / "SKILL.md").read_text(encoding="utf-8")
SPEC = "\n".join(
    p.read_text(encoding="utf-8")
    for p in [SPEC_DIR / "SKILL.md", *sorted((SPEC_DIR / "references").glob("*.md"))]
)


def _subcommands():
    ap = relay_cli.build_parser()
    for action in ap._actions:
        if getattr(action, "choices", None) and isinstance(action.choices, dict):
            return set(action.choices)
    return set()


class SkillCallsExistingCommands(unittest.TestCase):
    def test_every_relay_cli_call_is_a_real_subcommand(self):
        called = set(re.findall(r"relay_cli\.py\"? ([a-z][a-z-]+)", SKILL + HANDOFF + SPEC))
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

    def test_severity_table_not_reintroduced(self):
        self.assertNotIn("| `MINOR`만 있음 |", SKILL)
        self.assertNotIn("| 총 라운드 5회 초과 |", SKILL)

    def test_round_limits_removed(self):
        for phrase in ("total_round_limit", "MAX_TOTAL_ROUNDS", "라운드 한도"):
            self.assertNotIn(phrase, SKILL)
        review_py = (PLUGIN_ROOT / "scripts/relaylib/review.py").read_text(encoding="utf-8")
        for phrase in ("MAX_TOTAL_ROUNDS", "total_round_limit"):
            self.assertNotIn(phrase, review_py)
        tmpl = (PLUGIN_ROOT / "templates" / "implementer.md.tmpl").read_text(encoding="utf-8")
        review_md = (SKILL_DIR / "references" / "review.md").read_text(encoding="utf-8")
        self.assertIn("같은 패턴", tmpl)
        self.assertIn("같은 패턴", review_md)


ORCA_COMMAND = re.compile(r"(?<![\w-])orca (orchestration|terminal|worktree|skills|agent|repo|status|open)(?![\w-])")


class OrcaGuideIsTheSource(unittest.TestCase):
    """명령 문법은 Orca 가이드가 정본이다 — relay 문서는 Orca 스킬로 불러 따르고 스냅숏을 두지 않는다 (ADR 0003)."""

    def test_no_orca_command_snapshots(self):
        hits = [line.strip() for line in (SKILL + HANDOFF + SPEC).splitlines() if ORCA_COMMAND.search(line)]
        self.assertEqual(hits, [])

    def test_sessions_load_guides_through_orca_skills(self):
        start = (SKILL_DIR / "references" / "start.md").read_text(encoding="utf-8")
        for text in (start, HANDOFF_MD):
            self.assertIn("Skill 도구", text)
            self.assertIn("`orca-cli`", text)
        self.assertIn("`orchestration`", start)       # 진행자 세션은 Run 을 소유한다
        self.assertNotIn("`orchestration`", HANDOFF_MD)  # handoff 는 워크트리와 진행자만 띄운다 — Run 은 진행자 것

    def test_deviations_from_orca_defaults_sit_after_invariants(self):
        # 컴팩션 뒤에도 남게 SKILL.md 앞부분, 불변식 바로 다음에 둔다
        i, j, k = (SKILL_MD.index(h) for h in ("## 불변식", "## Orca 기본과 다른 점", "## 단계 목록"))
        self.assertLess(i, j)
        self.assertLess(j, k)


class SessionStructure(unittest.TestCase):
    """설계 세션은 relay:handoff 로 진행자 세션을 띄우고 끝난다 (ADR 0005·0010)."""

    def test_no_session_classification_or_depth_two(self):
        self.assertNotIn("세션 판정", SKILL_MD)
        self.assertNotIn("진행자 워커", SKILL)
        self.assertNotIn("SUB-DISPATCH", SKILL)
        self.assertNotIn("nested-depth", SKILL + HANDOFF)

    def test_old_inputs_stop_with_the_compat_line(self):
        entry = SKILL_MD.split("## 진입")[1].split("\n## ")[0]
        self.assertIn("T-NNN", entry)
        self.assertIn("relay 진행자:", entry)
        self.assertIn("3.0.0 은 구현 이슈만 받는다. spec 을 이슈로 옮기고 `relay:handoff` 로 시작한다", entry)

    def test_handoff_launch_line_tells_the_session_to_load_relay(self):
        # 회귀: 기동 줄만으로는 description 이 3회 중 1회 발동하지 않았다 (2026-11-03 eval)
        line = next(l for l in HANDOFF_MD.splitlines() if l.strip().startswith("relay: 구현 이슈 <이슈 URL>"))
        self.assertIn("Skill 도구로 relay 스킬을 먼저 부르고", line)
        self.assertIn("relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그>", SKILL_MD)

    def test_handoff_runs_both_checks_and_creates_the_issue_worktree(self):
        for phrase in ("relay_cli.py\" doctor", "relay_cli.py\" handoff-check", "--no-parent", "--base-branch main",
                       "--agent claude", "agent launch"):
            self.assertIn(phrase, HANDOFF_MD)
        self.assertTrue((SPEC_DIR / "references" / "spec-template.md").exists())
        self.assertFalse((HANDOFF_DIR / "references" / "spec-template.md").exists())
        self.assertFalse((SKILL_DIR / "references" / "spec-template.md").exists())
        self.assertFalse((SKILL_DIR / "references" / "design.md").exists())

    def test_spec_skill_exists_and_is_invocable(self):
        self.assertTrue((SPEC_DIR / "SKILL.md").exists())
        head = SPEC_MD.split("---")[1]
        self.assertNotIn("disable-model-invocation", head)
        self.assertIn('relay_cli.py" handoff-check', SPEC_MD)

    def test_handoff_recommends_relay_spec(self):
        entry = HANDOFF_MD.split("## 1. 구현 이슈를 쓴다")[1].split("\n## ")[0]
        self.assertIn("`relay:spec`", entry)

    def test_workers_run_in_the_issue_worktree_and_close_themselves(self):
        self.assertIn("--worktree current", SKILL_MD)
        self.assertNotIn("id:<wt>", SKILL)
        self.assertNotIn("worker-release", SKILL)
        self.assertNotIn("worker-retain", SKILL)
        finish = (SKILL_DIR / "references" / "finish.md").read_text(encoding="utf-8")
        self.assertIn("worker-keep-open", finish)
        self.assertIn("Closes #", finish)
        self.assertIn("태스크 도중 이슈가 바뀜: 반영 안 됨", finish)

    def test_judgment_subagent_runs_through_stop_md(self):
        # 판정 서브에이전트의 입출력 계약 (#23): 경로 입력, 스키마 검증, 판정 기록, judge 역할
        self.assertFalse((SKILL_DIR / "references" / "escalation.md").exists())
        stop = (SKILL_DIR / "references" / "stop.md").read_text(encoding="utf-8")
        for phrase in ("model judge", "judgment validate", "judgment-schema.json", ".ai/judgments/I-<n>.jN.json",
                       "Judged-by: claude/", "Relay-Done: I-<n>", "Agent 도구"):
            self.assertIn(phrase, stop)
        self.assertTrue((SKILL_DIR / "references" / "judgment-schema.json").exists())

    def test_stops_with_a_report_not_ask_or_decision_gates(self):
        # 진행자는 최상위라 ask 할 위 세션이 없다. decision gate 도 쓰지 않는다 (ADR 0008)
        self.assertNotRegex(SKILL, r"gate-(create|resolve|list)")
        self.assertNotIn("설계 세션에 `ask`", SKILL)
        self.assertNotIn("ask` 로 설계 세션", SKILL)
        self.assertIn("멈춤 보고", SKILL_MD)


# 지운 감독 루프의 흔적 (성공 기준 3, #19). Orca 가이드가 하는 일을 relay 문서가 다시 적지 않는다.
# 오탐을 보고 다듬는다 — 게이트 명령의 `--release`(cargo 등)는 잡지 않는다.
FORBIDDEN = [
    r"liveness", r"relay_cli\.py\"? startup", r"lookup_dispatch", r"confirm_delivery", r"STALL_MS", r"BLOCKED_RE",
    r"check --wait", r"agentWait", r"requiresAction", r"nextAction",
    r"(?<!--)\brelease\b", r"\bretain\b", r"worker-release", r"worker-retain", r"--retry-of",
    r"빈 대기", r"기동 실패 예산", r"nested-depth", r"SUB-DISPATCH",
]


class SupervisionStaysInOrca(unittest.TestCase):
    def test_no_forbidden_tokens_in_either_skill(self):
        docs = {p: p.read_text(encoding="utf-8") for d in (SKILL_DIR, HANDOFF_DIR, SPEC_DIR) for p in d.rglob("*.md")}
        hits = ["%s: %s" % (p.relative_to(PLUGIN_ROOT), pat) for p, text in docs.items() for pat in FORBIDDEN
                if re.search(pat, text)]
        self.assertEqual(hits, [])

    def test_release_flag_of_a_gate_is_not_a_hit(self):
        self.assertIsNone(re.search(r"(?<!--)\brelease\b", "게이트 명령: `cargo test --release`"))
        self.assertIsNotNone(re.search(r"(?<!--)\brelease\b", "워커를 release 한다"))

    def test_relay_cli_has_no_supervision_commands(self):
        self.assertFalse({"liveness", "startup"} & _subcommands())


EVALS = PLUGIN_ROOT / "evals"
EVAL_CASES = {"outcome-unknown", "prompt-blocked", "handoff-fires", "spec-violation-judge", "stop-reason-reinstruct",
              "resume-skips-done", "mutation-dirty", "tsc-silent", "handoff-not-relay"}


class Evals(unittest.TestCase):
    """eval 9케이스 (#24). handoff 기동 줄을 바꾸면 eval 프롬프트도 같이 바꾼다."""

    def test_the_nine_cases(self):
        self.assertEqual({p.name for p in EVALS.iterdir() if p.is_dir() and p.name != "results"}, EVAL_CASES)

    def test_coordinator_prompts_copy_the_handoff_launch_line(self):
        line = next(l.strip() for l in HANDOFF_MD.splitlines() if l.strip().startswith("relay: 구현 이슈 <이슈 URL>"))
        pattern = re.escape(line).replace(re.escape("<이슈 URL>"), r"\S+").replace(re.escape("<슬러그>"), r"[a-z0-9-]+")
        for case in sorted(EVAL_CASES - {"handoff-fires", "handoff-not-relay"}):
            prompt = (EVALS / case / "prompt.md").read_text(encoding="utf-8")
            self.assertRegex(prompt, pattern, case)
            self.assertNotIn("relay 진행자:", prompt, case)
            self.assertNotIn("You are a dispatched worker", prompt, case)

    def test_handoff_cases_check_which_skill_fired(self):
        for case, name in (("handoff-fires", "relay-not-fired.md"), ("handoff-fires", "skill-fired.md"),
                           ("handoff-not-relay", "handoff-not-fired.md"), ("handoff-not-relay", "relay-not-fired.md")):
            self.assertTrue((EVALS / case / "graders" / name).exists(), (case, name))


class Frontmatter(unittest.TestCase):
    """스킬 머리말이 YAML 로 읽혀야 스킬이 뜬다.

    회귀: 3.0.0 description 의 따옴표 없는 `relay: 구현 이슈` 가 YAML 을 깨뜨려 relay 스킬이 사라졌다
    (eval 2026-11-05, `Unknown skill: relay`).
    """

    def test_descriptions_are_safe_yaml_scalars(self):
        for md in (SKILL_MD, HANDOFF_MD, SPEC_MD):
            head = md.split("---")[1]
            for line in head.strip().splitlines():
                key, _, value = line.partition(": ")
                value = value.strip()
                if value[:1] in ("'", '"'):
                    self.assertEqual(value[-1], value[0], line)
                    if value[0] == "'":
                        self.assertNotIn("'", value[1:-1].replace("''", ""), line)
                else:
                    self.assertNotIn(": ", value, "%s: 따옴표 없는 값에 ': ' 가 있다" % key)
                    self.assertNotIn(" #", value, "%s: 따옴표 없는 값에 ' #' 가 있다" % key)

    def test_skill_names(self):
        self.assertIn("\nname: relay\n", SKILL_MD[:40])
        self.assertIn("\nname: handoff\n", HANDOFF_MD[:40])
        self.assertIn("\nname: spec\n", SPEC_MD[:40])


class SkillSkeleton(unittest.TestCase):
    def test_both_skill_mds_stay_within_500_lines(self):
        # 다시 비대해지는 것을 막는 상한 (분리 성공 기준). 컴팩션 생존은 리뷰에서 사람이 본다
        for text in (SKILL_MD, HANDOFF_MD):
            self.assertLessEqual(len(text.splitlines()), 500)

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
