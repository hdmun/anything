---
type: llm
---

The user asks to rewrite a wayfinder task ticket as a relay implementation issue, with no sub-issues, and forbids creating or editing the issue. This is the `relay:spec` job: write the issue body, then run the read-only pre-launch check. It is not a handoff.

The prompt forbids execution, so the response is a written plan; judge the plan.

PASS if the response:
1. Writes the body in the relay spec template format (reads or follows `references/spec-template.md`): changed files, acceptance criteria with a `게이트 명령:` line, and a 「사람이 할 일」 section in the issue itself (there are no sub-issues).
2. Plans to read the target code before writing the spec, or otherwise grounds the spec in the code.
3. Ends with `relay_cli.py handoff-check --issue <issue URL>` as a read-only check, fixing the body by its `→` lines on FAIL.
4. Does not launch a coordinator. Saying that `relay:handoff` is the next, separate step is fine.

FAIL if it plans `relay_cli.py doctor` plus an Orca `worktree create`/`agent launch` for the coordinator, snapshots the spec, starts implementer or reviewer workers, or splits the work into more than 5 tasks.
