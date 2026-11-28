#!/bin/bash
# Antigravity CLI(agy) 의 settings.json 에 statusLine 을 이 폴더의 statusline.sh 로 맞춘다. (macOS 용)
#
#   bash agy-statusline/install.sh            맞춘다
#   bash agy-statusline/install.sh --check    아무것도 쓰지 않고 결과만 본다
#   --home <dir>                              홈 폴더 대신 쓸 폴더 (시험용)
#
# 대상: ~/.gemini/antigravity-cli/settings.json (폴더가 있을 때만). 출력 약속은 README.md 에 있다.
# bash 3.2 + jq.

check=0
home=$HOME
while [ $# -gt 0 ]; do
  case $1 in
    --check) check=1 ;;
    --home) [ $# -ge 2 ] || { echo '사용법: install.sh [--check] [--home <dir>]' >&2; exit 2; }; home=$2; shift ;;
    --home=*) home=${1#--home=} ;;
    *) echo '사용법: install.sh [--check] [--home <dir>]' >&2; exit 2 ;;
  esac
  shift
done

here=${BASH_SOURCE[0]%/*}
[ "$here" = "${BASH_SOURCE[0]}" ] && here=.
here=$(cd "$here" && pwd)
script="$here/statusline.sh"
case $script in
  *[!A-Za-z0-9_./~+@%:,-]*) script="'${script//\'/\'\\\'\'}'" ;;
esac
COMMAND="bash $script"

# settings.json 하나의 statusLine 을 맞춘다. 다른 키와 키 순서는 그대로 둔다.
# 결과는 status 와 message 에 둔다. status: 그대로 / 다름 / 바꿈 / 실패
sync_settings() {
  local path=$1 shown=$2 text='' out rc nl json
  status='' message=''
  if [ -f "$path" ]; then
    if ! text=$(cat -- "$path" 2>&1); then
      status=실패 message="실패: $shown 을 읽지 못했다: ${text#cat: }"; return
    fi
  elif [ -e "$path" ]; then
    status=실패 message="실패: $shown 이 파일이 아니다"; return
  fi
  [[ $text =~ ^[[:space:]]*$ ]] && text='{}'

  out=$(jq -s -r --arg cmd "$COMMAND" '
    if length != 1 then "MULTI"
    elif (.[0] | type) != "object" then "NOTOBJ"
    else .[0] | {type: "command", command: $cmd} as $d
      | if has("statusLine") and (.statusLine | tojson) == ($d | tojson) then "SAME"
        else "CHANGE", (.statusLine = $d) end
    end' <<<"$text" 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    out=${out#jq: error (at <stdin>:*): }
    status=실패 message="실패: $shown 의 JSON 을 읽지 못했다: ${out%%$'\n'*}"; return
  fi
  case ${out%%$'\n'*} in
    MULTI) status=실패 message="실패: $shown 의 JSON 을 읽지 못했다: JSON 값이 하나가 아니다"; return ;;
    NOTOBJ) status=실패 message="실패: $shown 의 최상위가 객체가 아니다"; return ;;
    SAME) status=그대로; return ;;
  esac

  if [ $check = 1 ]; then status=다름; return; fi
  status=바꿈
  json=${out#*$'\n'}
  nl=$'\n'
  case $text in *$'\r\n'*) nl=$'\r\n'; json=${json//$'\n'/$'\r\n'} ;; esac
  # 제자리에서 덮어쓴다. 링크면 링크 대상에 쓴다.
  if ! out=$( { printf '%s%s' "$json" "$nl" >"$path"; } 2>&1 ); then
    status=실패 message="실패: $shown 을 쓰지 못했다: ${out##*: }"
  fi
}

dirs=() shownd=()
if [ -d "$home/.gemini/antigravity-cli" ]; then
  dirs+=("$home/.gemini/antigravity-cli"); shownd+=('~/.gemini/antigravity-cli')
fi

failed='' changed='' first=''
i=0
while [ $i -lt ${#dirs[@]} ]; do
  name="${shownd[$i]}/settings.json"
  sync_settings "${dirs[$i]}/settings.json" "$name"
  case $status in
    실패) [ -n "$failed" ] || failed=$message ;;
    다름|바꿈) [ -n "$first" ] || first=$status; changed="${changed:+$changed, }$name" ;;
  esac
  i=$((i + 1))
done

if [ -n "$failed" ]; then echo "$failed"
elif [ -n "$changed" ]; then echo "$first ($changed)"
else echo '그대로'
fi
