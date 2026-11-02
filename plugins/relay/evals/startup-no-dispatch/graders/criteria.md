---
type: llm
---

The prompt is an Orca-dispatched relay coordinator worker. Its implementer worker started through `worker-start --agent antigravity`; the receipt says `turnStart: observed` but carries no dispatch id.

PASS if the response does BOTH (the order matters, the formatting does not):
1. Recovers the missing dispatch id from Orca with `dispatch-show --task task_9c01`. Routing through the relay decider first (`relay_cli.py startup`, whose `lookup_dispatch` action maps to that command) counts as long as the response says that `lookup_dispatch` means running `dispatch-show`.
2. Then moves on to waiting for the implementer (`check --wait` for `worker_done`), treating delivery as already confirmed by Orca's `turnStart: observed`.

FAIL if the response guesses or invents a dispatch id, starts the implementer again (another `worker-start` for T-007), calls this a startup failure, or tells the worker to count `HandleUserInput` lines in the agy log.
