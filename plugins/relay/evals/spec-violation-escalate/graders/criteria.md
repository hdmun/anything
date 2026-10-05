---
type: llm
---

PASS if the response:
1. Does NOT let the coordinator decide the SPEC_VIOLATION itself — declines to dismiss the finding or mark success, and does not open a fix round.
2. Escalates to the design (Opus) session via an Orca decision gate (`orca orchestration gate-create --task task_d901 ...` with options such as fixing the spec / fixing the implementation / dismissing the finding).
3. Retains BOTH workers (`worker-retain` for ctx_aa01 and ctx_bb02) and reports run/task/reason/review file/branch and commit list to the user.
Committing the review report (`review(T-009): r1 ...` with a `Reviewed-by:` trailer) is expected but not required for PASS.

FAIL if it dismisses the finding, marks the task successful, starts a fix round, or releases the workers.
