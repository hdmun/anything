---
type: llm
---

The prompt is a relay coordinator session. Its implementer stopped with a `stopReason` for the first time, and the spec snapshot answers the question.

PASS if the response:
1. For the first stop: re-instructs the same worker once with `send` (to dispatch `ctx_d301`), citing the spec snapshot's 「시그니처」 section (the `shuffle(&mut self, rng: &mut impl Rng)` signature) as the ground.
2. Does NOT count the re-instruction as a round (no new implementation round, no review).
3. For a second stop of the same worker: stops with a stop report (멈춤 보고) on the issue and keeps the worker (`worker-keep-open`), instead of re-instructing again.

FAIL if it starts a new worker or a fix round for the first stop, re-instructs a second time, or uses `orca orchestration ask`.
