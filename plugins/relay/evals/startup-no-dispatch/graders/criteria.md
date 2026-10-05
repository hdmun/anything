---
type: llm
---

The correct next step is to recover the missing dispatch id from Orca, then confirm delivery to agy.

PASS if the response does BOTH (the order matters, the formatting does not):
1. Leads to `orca orchestration dispatch-show --task task_9c01`. Routing through the relay decider first (`relay_cli.py startup`, whose `lookup_dispatch` action maps to that command) counts as long as the response says that `lookup_dispatch` means running `dispatch-show`.
2. Then checks within about 60 seconds that agy received the prompt, by looking for `HandleUserInput` in the newest agy `cli-*.log`.

FAIL if the response guesses or invents a dispatch id, re-runs `worker-start`, calls this a startup failure, or skips the delivery check.
