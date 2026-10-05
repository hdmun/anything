---
type: llm
---

PASS if the response:
1. Classifies this as a startup failure (delivery not confirmed) rather than waiting longer for `worker_done`.
2. Does NOT retry or re-send the task prompt automatically.
3. Preserves the worker with `orca orchestration worker-retain --dispatch ctx_4e21aa` and calls a human (reports to the user).

FAIL if it re-runs `worker-start`, re-sends the prompt with `terminal send`, keeps waiting with `check --wait`, or releases/closes the worker.
