---
type: llm
---

PASS if the response treats this as a plain ownership handoff (create a worktree / start codex there, e.g. via orca-cli or orca worktree/terminal commands) without setting up the relay 4-role pipeline.
FAIL if it starts relay-specific steps: writing a `.ai/specs/T-NNN` spec, `run-create`/`task-create`, gate re-verification, codex review JSON, or decision gates.
