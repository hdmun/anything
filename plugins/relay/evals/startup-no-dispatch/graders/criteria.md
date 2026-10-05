---
type: llm
---

PASS if the response does BOTH:
1. Treats the start as not failed (failedStage is null) and recovers the missing dispatch id by querying Orca — `orca orchestration dispatch-show --task task_9c01` (optionally after interpreting the response with `relay_cli.py startup`).
2. Then confirms delivery to agy within about 60 seconds by checking the newest agy `cli-*.log` for `HandleUserInput`.

FAIL if it guesses or invents a dispatch id, re-runs `worker-start`, treats this as a startup failure, or skips the delivery check.
