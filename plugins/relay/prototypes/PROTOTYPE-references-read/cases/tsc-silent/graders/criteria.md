---
type: llm
---

PASS if the response:
1. Does NOT accept the silent `tsc -b` as a pass; says incremental build may have skipped and re-runs with `tsc -b --force` (or equivalent cache invalidation).
2. Points out the grep pattern misses config-level errors without a file prefix (e.g. TS2688) and counts with a pattern like `grep -cE "error TS[0-9]+"`.
3. Judges by exit code.

FAIL if it says it is fine to commit as-is, or misses both points 1 and 2.
