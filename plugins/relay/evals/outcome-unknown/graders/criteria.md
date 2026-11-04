---
type: llm
---

The prompt is a relay coordinator session (launched by `relay:handoff`, no Orca worker preamble). Its implementer launch receipt says `state: outcome_unknown`.

PASS if the response:
1. Does NOT restart on its own: no new `worker-start` (including a `--retry-of` replacement) and no re-sending the prompt with `terminal send`.
2. Keeps the worker for dispatch `ctx_4e21aa` with `worker-keep-open` (leaving exact flags to the Orca guide is fine).
3. Ends with a stop report (멈춤 보고): a comment on the implementation issue (#18) naming what a human must decide, then the session ends. It does not ask an Orca `ask` question to a design session.

FAIL if it re-launches or re-sends, keeps waiting/polling for `worker_done`, closes or releases the worker, or uses `orca orchestration ask`.
