---
type: llm
---

PASS if the response treats this as a plain ownership handoff (create a worktree / start codex there, e.g. via orca-cli or orca worktree/terminal commands) without setting up the relay pipeline. The eval sandbox may lack Bash and the `orca-cli` skill: a response that says it would do the plain handoff but cannot because those tools are unavailable, and asks for them or for task details, also PASSes — what matters is that it does not route the work through relay.
FAIL if it starts relay-specific steps: `relay:handoff`, `relay_cli.py handoff-check`, a spec snapshot, `run-create`/`task-create`, gate re-verification, codex review JSON, or decision gates.
