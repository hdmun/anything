#!/bin/bash
# macOS 용 install.sh·statusline.sh 시험. 임시 HOME 만 쓰고 실제 설정은 건드리지 않는다.
#   bash agy-statusline/test.sh
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
install="$here/install.sh"
statusline="$here/statusline.sh"
cmd="bash $here/statusline.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0 n=0

ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "     기대: $3"; echo "     실제: $2"; fails=$((fails + 1)); fi; }
newhome() { n=$((n + 1)); h="$tmp/home-$n"; mkdir -p "$h"; for d in "$@"; do mkdir -p "$h/$d"; done; }
strip() { sed $'s/\x1b\\[[0-9;]*m//g'; }

echo '== install.sh'
newhome .gemini/antigravity-cli
f="$h/.gemini/antigravity-cli/settings.json"
printf '{\n  "a": 1,\n  "statusLine": {\n    "type": "command",\n    "command": "python status.py"\n  },\n  "b": [\n    "C:\\\\x"\n  ]\n}\n' >"$f"
ok '--check 는 다름' "$(bash "$install" --home "$h" --check)" '다름 (~/.gemini/antigravity-cli/settings.json)'
ok '맞추면 바꿈' "$(bash "$install" --home "$h")" '바꿈 (~/.gemini/antigravity-cli/settings.json)'
ok '다시 --check 는 그대로' "$(bash "$install" --home "$h" --check)" '그대로'
ok '키 순서' "$(jq -c keys_unsorted "$f")" '["a","statusLine","b"]'
ok 'statusLine 값' "$(jq -c .statusLine "$f")" "$(jq -nc --arg c "$cmd" '{type:"command",command:$c}')"
ok '다른 값 보존' "$(jq -r '.b[0]' "$f")" 'C:\x'

newhome .gemini/antigravity-cli
ok 'settings.json 이 없으면 만든다' "$(bash "$install" --home "$h")" '바꿈 (~/.gemini/antigravity-cli/settings.json)'
ok '만든 파일' "$(jq -r .statusLine.type "$h/.gemini/antigravity-cli/settings.json")" command
newhome .gemini
ok '~/.gemini 만 있으면 그대로' "$(bash "$install" --home "$h")" '그대로'
ok '폴더를 만들지 않는다' "$([ -e "$h/.gemini/antigravity-cli" ] && echo yes || echo no)" no

newhome .gemini/antigravity-cli
printf '{ broken' >"$h/.gemini/antigravity-cli/settings.json"
r=$(bash "$install" --home "$h")
ok '깨진 JSON 은 실패:' "${r%%읽지 못했다*}" '실패: ~/.gemini/antigravity-cli/settings.json 의 JSON 을 '

echo '== statusline.sh'
newhome .gemini/antigravity-cli
export HOME="$h"
in=$(jq -nc --arg dir "$here" '{
  cwd: $dir, workspace: {current_dir: $dir},
  model: {id: "Gemini 4 Neon (Medium)", display_name: "Gemini 4 Neon (Medium)", effort: "medium"},
  context_window: {total_input_tokens: 16296, context_window_size: 1048576, used_percentage: 62, current_usage: {input_tokens: 2076}},
  quota: {
    "3p-5h": {remaining_fraction: 1, reset_time: "1970-01-01T00:00:00Z", reset_in_seconds: 0},
    "gemini-5h": {remaining_fraction: 0.98, reset_time: "2026-11-28T10:35:27Z", reset_in_seconds: 16140},
    "gemini-weekly": {remaining_fraction: 0.99, reset_time: "2026-12-03T13:08:17Z", reset_in_seconds: 601200}},
  vcs: {type: "git"}, cost: {total_usd: 0.4249},
  conversation_title: "맥 전용 상태 줄 sh 스크립트를 만들고 한글·CJK 漢字·이모지 🎉 의 폭을 두 칸으로 세어 자르는지 보는 아주 긴 대화 제목",
  terminal_width: 100}')

show() { echo "-- $1"; shift; out=$("$@" | strip); echo "$out" | sed 's/^/   /'; }
show '예시 입력 (terminal_width 100)' bash "$statusline" <<<"$in"
ok '모델 이름에서 (Medium) 를 뺀다' "$(echo "$out" | head -1 | cut -d'|' -f1)" '🤖 Gemini 4 Neon (medium) '
ok '2줄' "$(echo "$out" | sed -n 2p)" '🧠 ██████░░░░ 62% | 16k/1M | ⏳ 5h 2% (🔄 4h29m)  7d 1% (🔄 6d23h) | 💰 $0.42'
ok '캐시에 reset_at' "$(jq -c '[."gemini-5h" | has("reset_at"), has("reset_in_seconds")]' "$h/.gemini/antigravity-cli/statusline-quota.json")" '[true,false]'
show 'COLUMNS=80' env COLUMNS=80 bash "$statusline" <<<"$in"
ok 'COLUMNS=80 recap 폭은 80 - 14 이하' "$(echo "$out" | tail -1 | sed 's/^📝 recap: //' | jq -Rr '[explode[] | if (. >= 4352 and . <= 4447) or (. >= 11904 and . <= 42191) or (. >= 44032 and . <= 55203) or . >= 127744 then 2 else 1 end] | add | . <= 66')" true
show '빈 입력' bash "$statusline" </dev/null
ok '빈 입력' "$out" 'statusline: no input'
show '잘못된 입력' bash "$statusline" <<<'not json'
ok '잘못된 입력' "$out" 'statusline: no input'
show 'quota 없음 (캐시에서)' bash "$statusline" <<<'{"model":{"display_name":"Gemini 4 Neon"},"context_window":{"total_input_tokens":0,"context_window_size":0,"used_percentage":0,"current_usage":null}}'
ok 'quota 없을 때 캐시' "$out" '🤖 Gemini 4 Neon
⏳ 5h 2% (🔄 4h29m)  7d 1% (🔄 6d23h)'
jq -nc '{"gemini-5h": {remaining_fraction: 0.1, reset_time: "2000-01-01T00:00:00Z", reset_at: 946684800}, "gemini-weekly": {remaining_fraction: 0.5, reset_time: "2100-01-01T09:00:00+09:00"}}' >"$h/.gemini/antigravity-cli/statusline-quota.json"
show '리셋 지난 캐시' bash "$statusline" <<<'{"model":{"display_name":"Gemini"}}'
ok '리셋 지난 창은 0%·시간 없음' "$(echo "$out" | sed -n 2p | grep -cE '^⏳ 5h 0%  7d 50% \(🔄 [0-9]+d[0-9]+h\)$')" 1
show 'BOM 이 붙은 입력' bash "$statusline" < <(printf '\xef\xbb\xbf{"model":{"display_name":"X"},"conversation_title":"  제목   두칸  "}')
ok 'BOM 이 붙은 입력' "$(echo "$out" | sed -n '1p;3p')" '🤖 X
📝 recap: 제목 두칸'

echo
if [ $fails -eq 0 ]; then echo '모두 통과'; else echo "실패 $fails 개"; exit 1; fi
