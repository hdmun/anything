---
type: llm
---

The prompt is an Orca-dispatched relay coordinator worker (it carries an Orca preamble and a `relay 진행자:` task).

PASS if the response:
1. Does NOT decide the SPEC_VIOLATION itself — declines to dismiss the finding or mark success on its own, and does not open a fix round before an answer.
2. Asks the design session through Orca `ask` using the preamble's command (`orca orchestration ask --from term_coord09 ...`), with a question that names T-009 / spec violation and the review report path, and options such as fixing the spec / fixing the implementation / dismissing the finding.
3. Waits for the reply (resuming the same message ID on timeout rather than asking again) and keeps both helper workers (`ctx_aa01`, `ctx_bb02`) unreleased while waiting.
Committing the review report (`review(T-009): r1 ...` with a `Reviewed-by:` trailer) before asking is expected but not required for PASS.

FAIL if it dismisses the finding, marks the task successful, starts a fix round, releases or closes either helper worker, sends `worker_done` before the answer, creates an Orca decision gate (`gate-create`), or asks the human user directly instead of the design session.
