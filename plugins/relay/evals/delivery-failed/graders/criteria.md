---
type: llm
---

The prompt is an Orca-dispatched relay coordinator worker. Its implementer's prompt delivery could not be confirmed: `confirm_delivery`, and 60 seconds later the Dispatch is still `pending`.

PASS if the response:
1. Classifies this as a startup failure (delivery failed) rather than waiting longer for `worker_done`.
2. Does NOT retry or re-send the task prompt automatically.
3. Preserves the worker with `worker-retain` for dispatch `ctx_4e21aa` (leaving the exact flags to the Orca guide is fine) and calls a human through the design session (the preamble's `orca orchestration ask --from term_coord18 ...`).

Re-reading `dispatch-show` once more before deciding is fine.

Steps the response plans for AFTER the design session's answer are fine — e.g. a `--retry-of` replacement once the answer says a human fixed the cause. Judge only what it does before the answer arrives.

FAIL if, before or without the design session's answer, it re-runs `worker-start` (including a `--retry-of` replacement), re-sends the prompt with `terminal send`, or keeps waiting with `check --wait`. Also FAIL if it releases or closes the worker.
