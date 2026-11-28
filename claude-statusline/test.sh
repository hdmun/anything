#!/bin/bash
# macOS 용 install.sh·statusline.sh 시험. 임시 HOME 만 쓰고 실제 설정은 건드리지 않는다.
#   bash claude-statusline/test.sh
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
install="$here/install.sh"
statusline="$here/statusline.sh"
cmd="bash $here/statusline.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0 n=0

ok() { n=$((n + 1)); if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; echo "     기대: $3"; echo "     실제: $2"; fails=$((fails + 1)); fi; }
newhome() { n=$((n + 1)); h="$tmp/home-$n"; mkdir -p "$h"; for d in "$@"; do mkdir -p "$h/$d"; done; }
strip() { sed $'s/\x1b\\[[0-9;]*m//g'; }

echo '== install.sh'

newhome .claude .agent-accounts/claude/a .agent-accounts/claude/b
printf '{\n  "env": {\n    "A": "1"\n  },\n  "statusLine": {\n    "type": "command",\n    "command": "bash ~/.claude/statusline__.sh",\n    "padding": 0\n  },\n  "when": "2026-11-22T10:00:00Z",\n  "list": [\n    "x"\n  ],\n  "big": 12345678901234567890,\n  "z": true\n}\n' >"$h/.claude/settings.json"
all='~/.claude/settings.json, ~/.agent-accounts/claude/a/settings.json, ~/.agent-accounts/claude/b/settings.json'
ok '--check 는 다름' "$(bash "$install" --home "$h" --check)" "다름 ($all)"
ok '--check 는 쓰지 않는다' "$([ -e "$h/.agent-accounts/claude/a/settings.json" ] && echo yes || echo no)" no
ok '맞추면 바꿈' "$(bash "$install" --home "$h")" "바꿈 ($all)"
ok '두 번째는 그대로' "$(bash "$install" --home "$h")" '그대로'
ok '--check 도 그대로' "$(bash "$install" --home "$h" --check)" '그대로'
f="$h/.claude/settings.json"
ok '키 순서' "$(jq -c keys_unsorted "$f")" '["env","statusLine","when","list","big","z"]'
ok 'statusLine 값' "$(jq -c .statusLine "$f")" "$(jq -nc --arg c "$cmd" '{type:"command",command:$c}')"
ok '다른 값 보존' "$(jq -c '[.env.A, .when, .list, .z]' "$f")" '["1","2026-11-22T10:00:00Z",["x"],true]'
ok '큰 수 보존' "$(grep -c '"big": 12345678901234567890' "$f")" 1
ok 'LF 로 끝남' "$(tail -c 1 "$f" | od -An -c | tr -d ' ')" '\n'
ok 'CR 없음' "$(grep -c $'\r' "$f")" 0
ok '계정 폴더에도 씀' "$(jq -r .statusLine.command "$h/.agent-accounts/claude/a/settings.json")" "$cmd"

newhome .claude .claude-x .claude-y .claude-z .claude-m .agent-accounts/claude/a
printf '{\n  "a": 1\n}\n' >"$h/.claude-x/settings.json"
printf '{}\n' >"$h/.claude-z/.credentials.json"
printf '{}\n' >"$h/.claude-m/.claude.json"
printf '{}\n' >"$h/.claude-w.json"
all='~/.claude/settings.json, ~/.claude-m/settings.json, ~/.claude-x/settings.json, ~/.claude-z/settings.json, ~/.agent-accounts/claude/a/settings.json'
ok '서브 계정 폴더 고르기 (--check)' "$(bash "$install" --home "$h" --check)" "다름 ($all)"
ok '서브 계정 폴더 고르기' "$(bash "$install" --home "$h")" "바꿈 ($all)"
ok '서브 계정 다시 --check' "$(bash "$install" --home "$h" --check)" '그대로'
ok '서브 계정 키 순서' "$(jq -c keys_unsorted "$h/.claude-x/settings.json")" '["a","statusLine"]'
ok '빈 서브 계정 폴더는 건너뜀' "$([ -e "$h/.claude-y/settings.json" ] && echo yes || echo no)" no
ok '~/.claude-w.json 그대로' "$(cat "$h/.claude-w.json")" '{}'

newhome .claude
printf '{\r\n  "a": 1\r\n}\r\n' >"$h/real-settings.json"
ln -s "$h/real-settings.json" "$h/.claude/settings.json"
ok '링크도 바꿈' "$(bash "$install" --home "$h")" '바꿈 (~/.claude/settings.json)'
ok '링크는 그대로 링크' "$([ -L "$h/.claude/settings.json" ] && echo link)" link
ok 'CRLF 유지' "$(head -c 14 "$h/real-settings.json" | od -An -c | tr -s " " | sed "s/ *\$//")" ' { \r \n " a " : 1 , \r \n'
ok 'LF 만 있는 줄 없음' "$(tr -d '\r' <"$h/real-settings.json" | wc -l | tr -d ' ') $(grep -c $'\r$' "$h/real-settings.json")" '7 7'

newhome .claude
printf '{ broken' >"$h/.claude/settings.json"
r=$(bash "$install" --home "$h")
ok '깨진 JSON 은 실패:' "${r%%읽지 못했다*}" '실패: ~/.claude/settings.json 의 JSON 을 '
ok '깨진 JSON 파일은 그대로' "$(cat "$h/.claude/settings.json")" '{ broken'
printf '[1]' >"$h/.claude/settings.json"
ok '최상위가 배열이면 실패:' "$(bash "$install" --home "$h")" '실패: ~/.claude/settings.json 의 최상위가 객체가 아니다'
rm "$h/.claude/settings.json"; mkdir "$h/.claude/settings.json"
ok '폴더면 실패:' "$(bash "$install" --home "$h")" '실패: ~/.claude/settings.json 이 파일이 아니다'
newhome
ok '대상 폴더가 없으면 그대로' "$(bash "$install" --home "$h")" '그대로'
newhome .claude
ok 'settings.json 이 없으면 만든다' "$(bash "$install" --home "$h"; jq -r .statusLine.type "$h/.claude/settings.json")" "바꿈 (~/.claude/settings.json)
command"

echo '== statusline.sh'
newhome .claude
export CLAUDE_CONFIG_DIR="$h/.claude"
now=$(date +%s)
tr="$h/transcript.jsonl"
{
  echo '{"type":"system","subtype":"away_summary","content":"예전 요약"}'
  echo '{"type":"system","subtype":"away_summary","content":"맥 전용 상태 줄 sh 스크립트를 만들었다. 한글과 이모지 🎉 는 두 칸으로 세고, 터미널 폭에 맞춰 자른다. 끝에는 말줄임표가 붙는다. (turn off recaps in /config)"}'
  echo '{"type":"user","message":{"content":"away_summary 라는 글자만 든 줄"}}'
} >"$tr"
in=$(jq -nc --arg dir "$here" --arg tr "$tr" --argjson now "$now" '{
  model: {display_name: "Opus 5.5"}, effort: {level: "medium"},
  workspace: {current_dir: $dir}, transcript_path: $tr,
  context_window: {used_percentage: 62, total_input_tokens: 124000, context_window_size: 200000},
  rate_limits: {five_hour: {used_percentage: 41, resets_at: ($now + 7830)}, seven_day: {used_percentage: 59, resets_at: ($now + 255600)}},
  cost: {total_cost_usd: 1.234, total_duration_ms: 4980000}}')

show() { echo "-- $1"; shift; out=$("$@" | strip); echo "$out" | sed 's/^/   /'; }
show '예시 입력' bash "$statusline" <<<"$in"
show 'COLUMNS=80' env COLUMNS=80 bash "$statusline" <<<"$in"
ok 'COLUMNS=80 recap 폭은 80 - 14 이하' "$(echo "$out" | tail -1 | sed 's/^📝 recap: //' | jq -Rr '[explode[] | if (. >= 4352 and . <= 4447) or (. >= 11904 and . <= 42191) or (. >= 44032 and . <= 55203) or . >= 127744 then 2 else 1 end] | add | . <= 66')" true
show '빈 입력' bash "$statusline" </dev/null
ok '빈 입력' "$out" 'statusline: no input'
show '잘못된 입력' bash "$statusline" <<<'{ broken'
ok '잘못된 입력' "$out" 'statusline: no input'
show '값 없는 입력 {} (사용 한도는 캐시에서)' bash "$statusline" <<<'{}'
ok '캐시에서 사용 한도' "$(echo "$out" | grep -c '5h 41%')" 1
jq -nc --argjson now "$now" '{five_hour: {used_percentage: 90, resets_at: ($now - 10)}, seven_day: {used_percentage: 30, resets_at: ($now + 3600)}}' >"$CLAUDE_CONFIG_DIR/statusline-rate-limits.json"
show '리셋 지난 캐시' bash "$statusline" <<<'{"model":{"display_name":"Opus"}}'
ok '리셋 지난 창은 0%·시간 없음' "$(echo "$out" | sed -n 2p)" '🧠 ░░░░░░░░░░ 0% | 0/? | ⏳ 5h 0%  7d 30% (🔄 1h0m)'

echo
if [ $fails -eq 0 ]; then echo '모두 통과'; else echo "실패 $fails 개"; exit 1; fi
