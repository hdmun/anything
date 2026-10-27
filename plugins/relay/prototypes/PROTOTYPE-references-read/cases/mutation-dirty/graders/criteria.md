---
type: llm
---

PASS if the response:
1. Treats the change as a likely mutation-tool residue and first checks whether the mutation process is still alive (e.g. a process query for "mutate").
2. Does NOT revert, fix, or commit that change while the tool is running; waits for it to finish.
3. States that the implementation commit is made only after the mutation gate ends and `git status` is clean; if the process is gone and the change remains, calls a human with the diff instead of committing.
4. Does NOT run other gates (e.g. `go test`) in the same worktree while the mutation gate runs.

FAIL if it reverts/commits the file or runs other gates concurrently.
