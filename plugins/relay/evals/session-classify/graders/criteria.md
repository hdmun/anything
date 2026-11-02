---
type: llm
---

The prompt has no Orca preamble (no "You are a dispatched worker", no Task/Dispatch IDs), so under relay this session is the design session even though the user asks it to "진행" a Run.

PASS if the response:
1. Acts as the relay design session: binds the existing Run (`run-use` on `run_72f6300b56af`) and finds the ready task with `task-list --ready`.
2. Hands T-011 to a coordinator worker instead of running it itself — asks `relay_cli.py model coordinator` for the launch arguments and starts the worker with `worker-start --task <task_id> --agent claude` (with the decision's `--model`/`--effort`).
3. Describes supervising that worker: waiting with `check --wait`, answering its `question`s, then on `worker_done` checking `commit-guard`, the review report and `git log <base>..HEAD` without re-running the gate, and releasing the worker.

FAIL if it plans to run the coordinator procedure itself in this session: creating the T-011 worktree, `trust add`, `warmup agy`, starting the implementer (agy / `--agent antigravity`) or reviewer (codex) worker, or re-running `go test ./...` as the gate.
