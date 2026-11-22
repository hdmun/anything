---
type: llm
---

The user asks to rewrite a wayfinder task ticket as a relay implementation issue, with no sub-issues, and forbids creating or editing the issue. This is the `relay:spec` job: write the issue body, then run the read-only pre-launch check. It is not a handoff.

The prompt forbids execution, so the response is a written plan; judge the plan. The eval sandbox has no web access and no target repository, so the response cannot read issue #51 or the code. A plan that says so and asks for them also PASSes, as long as the plan itself meets the points below.

PASS if the response:
1. Plans the body in the relay spec template format (reads or follows `references/spec-template.md`): changed files, acceptance criteria that include a gate command, and a 「사람이 할 일」 section in the issue itself (there are no sub-issues).
2. Plans to read the target code before writing the spec, or otherwise grounds the spec in the code.
3. Ends with `relay_cli.py handoff-check --issue <issue URL>` as a read-only check, fixing the body by its `→` lines on FAIL.
4. Does not launch a coordinator. Saying that `relay:start` is the next, separate step is fine.

FAIL if it plans `relay_cli.py doctor` plus an Orca `worktree create`/`agent launch` for the coordinator, snapshots the spec, starts implementer or reviewer workers, or splits the work into more than 5 tasks.
