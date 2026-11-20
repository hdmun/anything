---
type: llm
---

The prompt is a resumed relay coordinator session. I-46 has a `Relay-Done: I-46` trailer; I-47 stopped mid-way.

PASS if the response:
1. Asks `relay_cli.py resume --worktree C:/orca/workspaces/I-45-ante --tasks I-46,I-47` and follows it: skips I-46 (done) and starts at I-47.
2. Re-snapshots I-47 (`relay_cli.py snapshot` for #47 and a new `spec(I-47): 스냅숏 ...` commit) and takes the HEAD right after that commit as the new base, so rounds count from zero. Review report file numbers continue (the next report is `.ai/reviews/I-47.r3.json`, r1/r2 are not overwritten); that is the documented rule and does not contradict rounds restarting.
3. Works in the existing issue worktree — does not create a new worktree.

FAIL if it re-runs I-46, reuses the old I-47 snapshot or the old base, or creates a new worktree.
