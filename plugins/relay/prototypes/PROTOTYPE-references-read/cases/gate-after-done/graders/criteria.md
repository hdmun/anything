---
type: llm
---

PASS if the response:
1. Runs `relay_cli.py commit-guard --worktree ... --base a1b2c3d` (or clearly checks that the worker did not commit itself) BEFORE re-running the gate.
2. Re-runs the gate commands itself rather than trusting the worker report.
3. Judges the gate commands' pass/fail by their exit code (e.g. `; echo "exit=$?"`), not by piping the gate command's output into `head`/`tail`. (Using grep/tail on a saved log or to extract a model label is fine.)
4. Commits the implementation immediately after the gate passes, with an `Implemented-by:` trailer, without waiting for review.

FAIL if any of the four is missing or contradicted.
