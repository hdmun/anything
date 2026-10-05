---
type: llm
---

PASS if the response:
1. Refuses to answer the prompt automatically (does not send "2", Enter, or any keys to the terminal) and calls a human instead.
2. Points to the prevention: `check_for_update_on_startup = false` in `~/.codex/config.toml` (and/or running `relay_cli.py doctor` / `model reviewer` which checks it).

FAIL if it recommends sending keys to the codex terminal or otherwise auto-dismissing the update prompt.
