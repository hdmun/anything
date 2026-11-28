#!/bin/bash
# Claude Code 상태 줄 (macOS 용). statusline.ps1 과 같은 3줄을 낸다.
# bash 3.2 + jq 1.7. 외부 명령은 jq 2번, git 1번(분리된 HEAD 면 2번), tail·grep 1번만 부른다.

IFS= read -r -d '' raw

# 1단계: 입력을 검사하고 bash 가 쓸 값만 꺼낸다.
vars=$(jq -r '
  def truthy: . != null and . != false and . != 0 and . != "" and . != [];
  if truthy then
    (if type == "object" then . else {} end) as $j
    | ($j.workspace.current_dir | if truthy then tostring else ($j.cwd | if truthy then tostring else "" end) end) as $dir
    | ($j.transcript_path | if truthy then tostring else "" end) as $tp
    | ($j.rate_limits | if truthy then tojson else "" end) as $rl
    | @sh "ok=1 dir=\($dir) tp=\($tp) rl=\($rl)"
  else "ok=0" end' <<<"$raw" 2>/dev/null)
ok=0
eval "$vars"
if [ "$ok" != 1 ]; then echo 'statusline: no input'; exit 0; fi

# git: 브랜치와 변경 여부를 status 한 번으로 얻는다.
gs='' sha=''
if [ -n "$dir" ] && [ -e "$dir" ]; then
  gs=$(git --no-optional-locks -C "$dir" status --porcelain=v2 --branch 2>/dev/null)
  case $gs in
    *'# branch.head (detached)'*) sha=$(git --no-optional-locks -C "$dir" rev-parse --short HEAD 2>/dev/null) ;;
  esac
fi

# rate_limits 는 첫 응답 전에는 없다 -> 계정 설정 폴더마다 마지막 값을 둔다.
rlcache="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-rate-limits.json"
rlc=''
if [ -n "$rl" ]; then
  { printf '%s' "$rl" >"$rlcache"; } 2>/dev/null
elif [ -f "$rlcache" ]; then
  rlc=$(<"$rlcache")
fi

# 2단계: transcript 끝 2MB 에서 away_summary 가 든 줄만 jq 로 넘겨 3줄을 만든다.
{
  if [ -n "$tp" ] && [ -f "$tp" ]; then
    tail -c 2097152 "$tp" 2>/dev/null | LC_ALL=C grep -aF '"away_summary"'
  fi
} | jq -R -s -r \
  --arg raw "$raw" --arg dir "$dir" --arg gs "$gs" --arg sha "$sha" --arg rlc "$rlc" \
  --arg cols "${COLUMNS:-}" --arg effenv "${CLAUDE_CODE_EFFORT_LEVEL:-}" '
  def truthy: . != null and . != false and . != 0 and . != "" and . != [];
  def C($code; $t): "\u001b[\($code)m\($t)\u001b[0m";
  def rep($n): if $n > 0 then . * $n else "" end;
  def clamp: if . < 0 then 0 elif . > 100 then 100 else . end;
  # [math]::Round 와 같은 은행가 반올림
  def bround: floor as $f | (. - $f) as $r
    | if $r > 0.5 then $f + 1 elif $r < 0.5 then $f elif ($f % 2) == 0 then $f else $f + 1 end;
  def fmt_tokens: if . == null then "?"
    elif . >= 1000000 then "\(. / 1000000 * 10 | round / 10)M"
    elif . >= 1000 then "\(. / 1000 | round)k"
    else tostring end;
  def fmt_span: (if . < 0 then 0 else . end | floor) as $s
    | ($s / 86400 | floor) as $d | (($s % 86400) / 3600 | floor) as $h | (($s % 3600) / 60 | floor) as $m
    | if $d > 0 then "\($d)d\($h)h" elif $h > 0 then "\($h)h\($m)m" else "\($m)m" end;
  def fmt_money: (. * 100 | round) as $c
    | "\($c / 100 | floor).\($c % 100 | if . < 10 then "0\(.)" else tostring end)";
  # 쓴 % -> 색 (50 미만 초록, 80 미만 노랑, 그 이상 빨강)
  def lvl: if . >= 80 then "31" elif . >= 50 then "33" else "32" end;
  def leaf: (sub("/+$"; "") | split("/") | last) as $l | if ($l // "") == "" then . else $l end;
  # 폭: 한글·CJK·이모지는 2칸. 글자 묶음(결합 문자·ZWJ·국기)의 첫 코드 포인트로 정한다.
  def wide: (. >= 4352 and . <= 4447) or (. >= 11904 and . <= 42191) or (. >= 44032 and . <= 55203)
    or (. >= 63744 and . <= 64255) or (. >= 65280 and . <= 65376) or . >= 127744;
  def extend: (. >= 768 and . <= 879) or (. >= 4448 and . <= 4607) or . == 8204 or . == 8205
    or (. >= 8400 and . <= 8447) or (. >= 65024 and . <= 65039) or (. >= 65056 and . <= 65071)
    or (. >= 127995 and . <= 127999) or (. >= 917536 and . <= 917631) or (. >= 917760 and . <= 917999);
  def ri: . >= 127462 and . <= 127487;
  def clusters: reduce explode[] as $c ([];
    if length > 0 and (($c | extend) or (.[length - 1] | last) == 8205
        or (($c | ri) and (.[length - 1] | length) == 1 and (.[length - 1][0] | ri)))
    then .[length - 1] += [$c] else . + [[$c]] end);
  def fit($max): reduce clusters[] as $g ({s: "", w: 0, done: false};
    if .done then . else
      (if ($g[0] | wide) then 2 else 1 end) as $cw
      | if .w + $cw > $max - 1 then .s += "…" | .done = true else .s += ($g | implode) | .w += $cw end
    end) | .s;

  . as $tail
  | ($raw | fromjson) as $j0 | (if ($j0 | type) == "object" then $j0 else {} end) as $j
  | (now | floor) as $now

  # ---------- line 1: model / directory / git ----------
  | ([[$j.effort, $j.model.effort, $j.effort_level][]
      | if type == "string" then select(. != "") elif type == "object" and (.level | truthy) then .level else empty end]
     | .[0] // (if $effenv != "" then $effenv else null end)) as $effort
  | ($gs | split("\n")) as $gl
  | ([$gl[] | select(startswith("# branch.head ")) | .[14:]] | .[0]) as $head
  | (if $head == "(detached)" then (if $sha != "" then $sha else null end) else $head end) as $branch
  | [ (if ($j.model.display_name | truthy) then
        "🤖 " + C("1;36"; $j.model.display_name)
        + (if $effort then " " + C("2"; "(\($effort))") else "" end)
      else empty end),
      (if $dir != "" then "📁 " + C("34"; $dir | leaf) else empty end),
      (if ($branch | truthy) then
        "🌿 " + C("35"; $branch) + (if any($gl[]; . != "" and (startswith("#") | not)) then C("33"; "*") else "" end)
      else empty end)
    ] as $line1

  # ---------- line 2: context / limits / cost / time ----------
  | $j.context_window as $cw
  | (if ($cw | truthy) and $cw.used_percentage != null then ($cw.used_percentage | clamp) else 0 end) as $pct
  | ($pct / 100 * 10 | bround) as $filled
  | ($pct | lvl) as $col
  | ($j.rate_limits | if truthy then {rl: ., stale: false}
      else {rl: (try ($rlc | fromjson) catch null), stale: true} end) as $R
  | ([ if ($R.rl | type) == "object" then
        (["five_hour", "5h"], ["seven_day", "7d"], ["spend_limit", "spend"]) as [$k, $lab]
        | $R.rl[$k] as $o
        | select(($o | type) == "object" and $o.used_percentage != null)
        | ($R.stale and ($o.resets_at | truthy) and $o.resets_at <= $now) as $expired
        | (if $expired then 0 else ($o.used_percentage | clamp) end) as $u
        | $lab + " " + C($u | lvl; "\($u | round)%")
          + (if ($o.resets_at | truthy) and ($expired | not)
             then " " + C("2"; "(🔄 " + ($o.resets_at - $now | fmt_span) + ")") else "" end)
      else empty end ]) as $lims
  | [ "🧠 " + C($col; "█" | rep($filled)) + C("90"; "░" | rep(10 - $filled)) + " " + C($col; "\($pct | round)%"),
      C("2"; (if ($cw | truthy) and $cw.total_input_tokens != null then $cw.total_input_tokens else 0 end | fmt_tokens)
        + "/" + (if ($cw | truthy) and ($cw.context_window_size | truthy) then $cw.context_window_size | fmt_tokens else "?" end)),
      (if ($lims | length) > 0 then "⏳ " + ($lims | join("  ")) else empty end),
      (if $j.cost.total_cost_usd != null then "💰 " + C("32"; "$" + ($j.cost.total_cost_usd | fmt_money)) else empty end),
      (if $j.cost.total_duration_ms != null then "⏱ " + ($j.cost.total_duration_ms / 1000 | fmt_span) else empty end)
    ] as $line2

  # ---------- line 3: latest recap (away_summary) from transcript ----------
  | ([ $tail | split("\n") | reverse[]
       | (try fromjson catch null)
       | select(type == "object" and .subtype == "away_summary" and (.content | truthy))
       | .content | if type == "string" then . else tostring end ] | .[0]) as $recap
  | (if $recap then
      ($recap | sub("\\s*\\(turn off recaps in /config\\)\\s*$"; "") | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")) as $r
      | ($cols | gsub("\\s"; "") | if test("^[+-]?[0-9]+$") then tonumber else 0 end | if . > 0 then . else 120 end) as $c
      | "📝 " + C("90"; "recap:") + " " + ($r | fit($c - 14))
    else null end) as $line3

  # ---------- output ----------
  | (" " + C("90"; "|") + " ") as $sep
  | (if ($line1 | length) > 0 then $line1 | join($sep) else empty end),
    (if ($line2 | length) > 0 then $line2 | join($sep) else empty end),
    (if $line3 then $line3 else empty end)
'
