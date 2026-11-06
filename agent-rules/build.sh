#!/bin/sh
# 규칙 원본(agent-rules/)을 합쳐 CLAUDE.md·AGENTS.md 를 만든다.
#
#   sh agent-rules/build.sh            이 저장소의 CLAUDE.md, AGENTS.md 를 다시 만든다
#   sh agent-rules/build.sh --global   전역 CLAUDE.md, AGENTS.md 도 다시 만든다
#   sh agent-rules/build.sh --check    파일은 그대로 두고, 다시 만들어야 하면 exit 1
#   --force                            --global 에서 생성 표시가 없는 전역 파일도 덮어쓴다
#
# 파일 이름 규칙은 agent-rules/README.md 에 있다.
set -eu
export LC_ALL=C # 파일 합치는 순서를 로캘과 상관없이 고정한다

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; }

mode=build global=0 force=0
for arg in "$@"; do
  case $arg in
    --check) mode=check ;;
    --global) global=1 ;;
    --force) force=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "build.sh: 모르는 인자 '$arg'" >&2; usage >&2; exit 2 ;;
  esac
done

src=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$src/.." && pwd)
marker='<!-- 생성 파일'
codex_limit=32768 # Codex 기본 project_doc_max_bytes

# Windows 경로(C:\...)로 들어온 환경 변수를 sh 가 쓰는 경로로 바꾼다
unix_path() {
  if command -v cygpath > /dev/null 2>&1; then cygpath -u "$1"; else printf '%s\n' "$1"; fi
}

# 생성 파일에 적을 경로 — Windows 에서는 C:/... 로 적어 탐색기·에디터에서 바로 열리게 한다
shown_path() {
  if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

# render <범위 폴더> <claude|codex> <원본 위치> <다시 만드는 명령>
render() {
  printf '%s: 직접 고치지 않는다. 원본은 %s 이고 `%s` 로 다시 만든다 -->\n' "$marker" "$3" "$4"
  for f in "$1"/*.md; do
    [ -e "$f" ] || continue
    case ${f##*/} in
      *.claude.md) [ "$2" = claude ] || continue ;;
      *.codex.md) [ "$2" = codex ] || continue ;;
    esac
    printf '\n'
    awk '{ sub(/\r$/, ""); print }' "$f" # CRLF 체크아웃과 끝 줄바꿈 누락을 정리한다
  done
}

stale=0 refused=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# emit <만들 파일> <claude|codex> <project|global>
emit() {
  dest=$1 tool=$2 scope=$3
  if [ "$scope" = global ]; then
    # 전역 파일은 저장소 밖에 있으므로 원본 위치를 절대 경로로 적는다
    render "$src/global" "$tool" "$(shown_path "$src/global")/" "sh agent-rules/build.sh --global" > "$tmp"
  else
    render "$src/project" "$tool" "agent-rules/project/" "sh agent-rules/build.sh" > "$tmp"
  fi

  size=$(wc -c < "$tmp" | tr -d ' ')
  if [ "$tool" = codex ] && [ "$size" -gt "$codex_limit" ]; then
    echo "경고: $dest 가 ${size}바이트다 — Codex 는 기본 ${codex_limit}바이트까지만 읽는다" >&2
  fi

  if [ -f "$dest" ] && tr -d '\r' < "$dest" | cmp -s - "$tmp"; then
    echo "그대로: $dest"
    return
  fi

  if [ "$mode" = check ]; then
    echo "다시 만들어야 한다: $dest" >&2
    stale=1
    return
  fi

  if [ "$scope" = global ] && [ -f "$dest" ]; then
    if ! head -n 1 "$dest" | grep -qF "$marker" && [ "$force" = 0 ]; then
      echo "건너뜀: $dest — 생성 표시가 없다. 내용을 agent-rules/global/ 로 옮긴 뒤 --force 로 덮어쓴다" >&2
      refused=1
      return
    fi
    # 전역 파일은 git 밖에 있다 — 바뀌는 줄을 보여주고 이전 파일을 남긴다
    tr -d '\r' < "$dest" | diff -u --label "$dest (이전)" --label "$dest (새)" - "$tmp" || true
    cp "$dest" "$dest.prev"
  fi

  cat "$tmp" > "$dest"
  echo "만듦: $dest"
}

emit "$root/CLAUDE.md" claude project
emit "$root/AGENTS.md" codex project

if [ "$global" = 1 ]; then
  claude_home=$(unix_path "${CLAUDE_CONFIG_DIR:-$HOME/.claude}")
  codex_home=$(unix_path "${CODEX_HOME:-$HOME/.codex}")
  emit "$claude_home/CLAUDE.md" claude global
  emit "$codex_home/AGENTS.md" codex global
fi

if [ "$stale" = 1 ]; then
  echo "build.sh: 생성 파일이 원본과 다르다 — sh agent-rules/build.sh 를 실행한다" >&2
  exit 1
fi
[ "$refused" = 0 ] || exit 1
