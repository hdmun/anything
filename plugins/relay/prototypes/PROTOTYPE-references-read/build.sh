#!/usr/bin/env bash
# PROTOTYPE: 변형 플러그인 4개를 out/ 에 만든다
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); src="$here/../../skills/relay"; out="$here/out"
rm -rf "$out"; mkdir -p "$out"
for v in v0-monolith v1-pointer v2-imperative v3-entry-table; do
  d="$out/$v"; mkdir -p "$d/.claude-plugin" "$d/skills/relay"
  printf '{"name":"relay","version":"0.0.0-proto-%s","description":"PROTOTYPE"}\n' "$v" > "$d/.claude-plugin/plugin.json"
  cp -r "$src/references" "$d/skills/relay/"; cp -r "$here/cases" "$d/evals"
  python "$here/variant.py" "$v" "$src/SKILL.md" "$d/skills/relay"
done
ls "$out"
