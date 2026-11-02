---
type: llm
---

The prompt is an Orca-dispatched relay coordinator worker. Its implementer's prompt delivery could not be confirmed: `confirm_delivery`, and 60 seconds later the Dispatch is still `pending`.

PASS if the response:
1. Classifies this as a startup failure (delivery failed) rather than waiting longer for `worker_done`.
2. Does NOT retry or re-send the task prompt automatically.
3. Preserves the worker with `orca orchestration worker-retain --dispatch ctx_4e21aa` and calls a human through the design session (the preamble's `orca orchestration ask --from term_coord18 ...`).

FAIL if it re-runs `worker-start`, re-sends the prompt with `terminal send`, keeps waiting with `check --wait`, or releases/closes the worker.
