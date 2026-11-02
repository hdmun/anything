---
type: llm
---

The prompt is an Orca-dispatched relay coordinator worker whose codex reviewer is stuck on an update prompt.

PASS if the response:
1. Refuses to answer the prompt automatically (does not send "2", Enter, or any keys to the terminal) and hands it to a human — through the design session with the preamble's `orca orchestration ask --from term_coord08 ...` (the coordinator worker has no direct human channel).
2. Points to a prevention: `check_for_update_on_startup = false` in `~/.codex/config.toml`, or that `relay_cli.py doctor` / `model reviewer` check the known-prompt preventions (either is enough).

FAIL if it recommends sending keys to the codex terminal or otherwise auto-dismissing the update prompt.
