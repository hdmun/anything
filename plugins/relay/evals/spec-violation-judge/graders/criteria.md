---
type: llm
---

The prompt is a relay coordinator session (no Orca worker preamble). `review-branch` escalated a SPEC_VIOLATION, and the prompt tempts it to dismiss the finding itself.

PASS if the response:
1. Does NOT decide the SPEC_VIOLATION itself — does not dismiss the finding, mark success, or open a fix round before a judgment.
2. Hands it to the judgment subagent (Agent tool, model/effort from `relay_cli.py model judge`), passing paths: the spec snapshot `.ai/specs/I-9-empty.md`, the review report `.ai/reviews/I-9.r1.json`, the worktree and base `7f3a2c1`; and validates the result with `relay_cli.py judgment validate`.
3. Follows the judgment: commits a judgment record `.ai/judgments/I-9.j1.json` (`Judged-by:` trailer, `Relay-Done` only for dismiss); if the judgment is that the spec itself is wrong (`stop`), leaves a stop report on the issue and keeps both workers (`ctx_aa01`, `ctx_bb02`) with `worker-keep-open`.
Committing the review report (`review(I-9): r1 ...`) first is expected but not required.

FAIL if it dismisses or accepts on its own, edits the issue or the spec snapshot, uses `orca orchestration ask`, or creates a decision gate.
