---
type: llm
---

The prompt has no Orca preamble and no relay launch line; the user hands over a written implementation issue. Under relay 3.0.0 this session is the design session, and it should hand the issue to a coordinator session with `relay:handoff`.

The prompt forbids execution, so the response is a written plan; judge the plan. Reading the issues, the spec template or the target code first is fine.

PASS if the response:
1. Plans both checks, run to completion before launching: `relay_cli.py doctor` and `relay_cli.py handoff-check --issue <issue URL>`, and launches nothing if either has a FAIL.
2. Launches the coordinator with Orca `worktree create` for an issue worktree named `I-42-<slug>`, with `--no-parent`, `--base-branch main`, `--agent claude`, the model/effort from `relay_cli.py model coordinator`, and the handoff launch line (`relay: 구현 이슈 <URL> / 슬러그: <slug> — Skill 도구로 relay 스킬을 먼저 부르고 ...`) as the prompt. Mentioning `agent launch` for an existing worktree (resume) is fine.
3. Ends after launching — does not supervise the Run.

FAIL if it runs the coordinator procedure itself in this session: snapshotting the spec, `run-create`/`task-create`, starting implementer (agy / `--agent antigravity`) or reviewer (codex) workers, or running gates.
