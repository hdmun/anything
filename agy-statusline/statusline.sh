#!/bin/bash
# Antigravity CLI(agy) 상태 줄 (macOS 용). statusline.ps1 과 같은 3줄을 낸다.
# bash 3.2 + jq 1.7. agy 는 300ms 간격으로 부르고 5초면 끊으므로
# 외부 명령은 jq 2번, git 1번(분리된 HEAD 면 2번)만 부른다.

IFS= read -r -d '' raw
raw=${raw#$'\xef\xbb\xbf'}

# 1단계: 입력을 검사하고 git 에 쓸 폴더만 꺼낸다.
vars=$(jq -r '
  def truthy: . != null and . != false and . != 0 and . != "" and . != [];
  if truthy then
    (if type == "object" then . else {} end) as $j
    | ($j.workspace.current_dir | if truthy then tostring else ($j.cwd | if truthy then tostring else "" end) end) as $dir
    | (if ($j.vcs | truthy | not) or $j.vcs.type == "git" then 1 else 0 end) as $git
    | @sh "ok=1 dir=\($dir) isgit=\($git)"
  else "ok=0" end' <<<"$raw" 2>/dev/null)
ok=0
eval "$vars"
if [ "$ok" != 1 ]; then echo 'statusline: no input'; exit 0; fi

gs='' sha=''
if [ "$isgit" = 1 ] && [ -n "$dir" ] && [ -e "$dir" ]; then
  gs=$(git --no-optional-locks -C "$dir" status --porcelain=v2 --branch 2>/dev/null)
  case $gs in
    *'# branch.head (detached)'*) sha=$(git --no-optional-locks -C "$dir" rev-parse --short HEAD 2>/dev/null) ;;
  esac
fi

# quota 는 첫 응답 전에는 없다 -> agy 설정 폴더에 마지막 값을 둔다.
# reset_in_seconds 는 상대값이라 캐시에는 절대 시각 reset_at(유닉스 초)으로 둔다.
qtcache="$HOME/.gemini/antigravity-cli/statusline-quota.json"
old=''
if [ -f "$qtcache" ]; then old=$(<"$qtcache"); fi

# 2단계: 첫 줄은 새 캐시 내용(바뀌지 않았으면 빈 줄), 그 뒤가 상태 줄이다.
out=$(jq -n -r \
  --arg raw "$raw" --arg dir "$dir" --arg gs "$gs" --arg sha "$sha" --arg old "$old" --arg cols "${COLUMNS:-}" '
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
  # ISO 8601 -> 유닉스 초. 시간대가 없으면 로컬 시각으로 본다. 못 읽으면 null.
  def parse_time: try (
      capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})[T ](?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})(?<f>[.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$")
      | ("\(.d)T\(.t)Z" | fromdateiso8601) as $base
      | (if .f then ("0" + .f | tonumber) else 0 end) as $frac
      | (if .z == "Z" then 0
         elif .z then (.z | gsub(":"; "")) as $z
           | ($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60 | if $z[0:1] == "-" then -. else . end
         else (now | floor) as $t | ($t | localtime | mktime) - $t end) as $off
      | $base + $frac - $off
    ) catch null;
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
  def intarg: tostring | gsub("\\s"; "") | if test("^[+-]?[0-9]+$") then tonumber else 0 end;

  ($raw | fromjson) as $j0 | (if ($j0 | type) == "object" then $j0 else {} end) as $j
  | (now | floor) as $now

  # ---------- line 1: model / directory / git ----------
  | (if ($j.model | truthy) and ($j.model.effort | type) == "string" and $j.model.effort != ""
     then $j.model.effort else null end) as $effort
  | ($gs | split("\n")) as $gl
  | ([$gl[] | select(startswith("# branch.head ")) | .[14:]] | .[0]) as $head
  | (if $head == "(detached)" then (if $sha != "" then $sha else null end) else $head end) as $branch
  | [ (if ($j.model | truthy) and ($j.model.display_name | truthy) then
        ($j.model.display_name | tostring
         | if $effort then
             ($effort | gsub("(?<c>[.*+?^${}()|\\[\\]\\\\/-])"; "\\\(.c)")) as $re
             | sub("\\s*\\(" + $re + "\\)\\s*$"; ""; "i") | sub("^\\s+"; "") | sub("\\s+$"; "")
           else . end) as $name
        | "🤖 " + C("1;36"; $name) + (if $effort then " " + C("2"; "(\($effort))") else "" end)
      else empty end),
      (if $dir != "" then "📁 " + C("34"; $dir | leaf) else empty end),
      (if ($branch | truthy) then
        "🌿 " + C("35"; $branch) + (if any($gl[]; . != "" and (startswith("#") | not)) then C("33"; "*") else "" end)
      else empty end)
    ] as $line1

  # ---------- line 2: context / quota / cost ----------
  | $j.context_window as $cw
  | ([ if ($cw | truthy) and $cw.used_percentage != null
          and (($cw.context_window_size // 0) > 0 or $cw.used_percentage > 0 or $cw.current_usage != null) then
        ($cw.used_percentage | clamp) as $pct | ($pct / 100 * 10 | bround) as $filled | ($pct | lvl) as $col
        | "🧠 " + C($col; "█" | rep($filled)) + C("90"; "░" | rep(10 - $filled)) + " " + C($col; "\($pct | round)%"),
          (if $cw.total_input_tokens != null and ($cw.context_window_size // 0) > 0 then
            C("2"; ($cw.total_input_tokens | fmt_tokens) + "/" + ($cw.context_window_size | fmt_tokens))
           else empty end)
      else empty end ]) as $ctx

  | (try ($old | fromjson) catch null) as $prev
  | (if ($j.quota | truthy) then
      ($j.quota | if type == "object" then with_entries(.value |= (
          if type == "object" then
            . as $o | del(.reset_in_seconds)
            + (if $o.reset_in_seconds != null and $o.reset_in_seconds > 0
               then {reset_at: ($now + ($o.reset_in_seconds | bround))} else {} end)
          else . end)) else . end) as $saved0
      # reset_at 은 부를 때마다 1~2초 흔들린다: 캐시 값과 가까우면 캐시 값을 쓴다
      | ($saved0 | if type == "object" and ($prev | type) == "object" then with_entries(
          $prev[.key] as $pv
          | if (.value | type) == "object" and (.value | has("reset_at")) and ($pv | type) == "object"
               and $pv.reset_at != null and (($pv.reset_at - .value.reset_at) | fabs) <= 5
            then .value.reset_at = $pv.reset_at else . end) else . end | tojson) as $txt
      # 바뀌지 않았으면 쓰지 않는다
      | {qt: $j.quota, write: (if $txt != $old then $txt else "" end)}
    else
      {write: "", qt: ($prev | if type == "object" then with_entries(.value |= (
          if type == "object" then
            (if .reset_at != null then .reset_at elif (.reset_time | truthy) then (.reset_time | parse_time) else null end) as $ra
            # 캐시의 창이 이미 리셋됐다 -> 0%, 리셋 시간 없음
            | if $ra != null and $ra <= $now then .remaining_fraction = 1 | del(.reset_time)
              elif $ra != null then .reset_in_seconds = ($ra - $now)
              else . end
          else . end)) else null end)}
    end) as $Q
  | $Q.qt as $qt
  | (if ($qt | type) == "object" then
      (if ($j.model | truthy) then "\($j.model.id // "") \($j.model.display_name // "")" else "" end) as $mk
      | (if ($mk | test("gemini"; "i")) then [["gemini-5h", "5h"], ["gemini-weekly", "7d"]]
         else [["3p-5h", "5h"], ["3p-weekly", "7d"]] end) as $buckets
      | ([ $buckets[] as [$k, $lab]
           | select($qt | has($k)) | $qt[$k] as $o
           | select(($o | truthy) and ($o | type) == "object" and $o.disabled != true and $o.remaining_fraction != null)
           | (100 - ($o.remaining_fraction * 100 | clamp)) as $u
           | (if $o.reset_in_seconds != null and $o.reset_in_seconds > 0 then $o.reset_in_seconds
              elif ($o.reset_time | truthy) then ($o.reset_time | parse_time) as $t
                | if $t != null and $t > $now then $t - $now else 0 end
              else 0 end) as $rs
           | $lab + " " + C($u | lvl; "\($u | round)%")
             + (if $rs > 0 then " " + C("2"; "(🔄 " + ($rs | fmt_span) + ")") else "" end) ]) as $main
      | if ($main | length) > 0 then $main else
          [ $qt | to_entries[] | .key as $name | .value as $o
            | select(($o | truthy) and ($o | type) == "object" and $o.disabled != true and $o.remaining_fraction != null)
            | (100 - ($o.remaining_fraction * 100 | clamp)) as $u
            | $name + " " + C($u | lvl; "\($u | round)%")
              + (if $o.reset_in_seconds != null and $o.reset_in_seconds > 0
                 then " " + C("2"; "(🔄 " + ($o.reset_in_seconds | fmt_span) + ")") else "" end) ]
        end
    else [] end) as $lims
  | ($ctx
     + (if ($lims | length) > 0 then ["⏳ " + ($lims | join("  "))] else [] end)
     + (if ($j.cost | truthy) and $j.cost.total_usd != null then ["💰 " + C("32"; "$" + ($j.cost.total_usd | fmt_money))] else [] end)
    ) as $line2

  # ---------- line 3: conversation title as summary ----------
  | (if ($j.conversation_title | type) == "string" and $j.conversation_title != "" then
      ($j.conversation_title | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "")) else null end) as $recap
  | (if ($recap | truthy) then
      ($cols | intarg | if . > 0 then . else ($j.terminal_width | if truthy then intarg else 0 end) end
       | if . > 0 then . else 120 end) as $c
      | "📝 " + C("90"; "recap:") + " " + ($recap | fit([10, $c - 14] | max))
    else null end) as $line3

  # ---------- output ----------
  | (" " + C("90"; "|") + " ") as $sep
  | $Q.write,
    (if ($line1 | length) > 0 then $line1 | join($sep) else empty end),
    (if ($line2 | length) > 0 then $line2 | join($sep) else empty end),
    (if $line3 then $line3 else empty end)
' 2>/dev/null)

{ IFS= read -r newcache; IFS= read -r -d '' lines; } <<<"$out"
if [ -n "$newcache" ]; then { printf '%s' "$newcache" >"$qtcache"; } 2>/dev/null; fi
printf '%s' "$lines"
