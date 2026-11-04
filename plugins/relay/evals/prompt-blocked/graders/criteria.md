---
type: llm
---

The prompt is a relay coordinator session whose codex reviewer is stuck on an update prompt.

PASS if the response:
1. Refuses to answer the prompt automatically (does not send "2", Enter, or any keys to the terminal, and does not offer keys as options) and hands it to a human, who handles it in that worker terminal. Telling the human directly or leaving a stop report (멈춤 보고) is fine; an Orca `ask` to a design session is not — there is none.
2. Points to a prevention: `check_for_update_on_startup = false` in `~/.codex/config.toml`, or that `relay_cli.py doctor` checks the known-prompt preventions (either is enough).

FAIL if it recommends sending keys to the codex terminal or otherwise auto-dismissing the update prompt, or uses `orca orchestration ask`.
