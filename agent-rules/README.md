# agent-rules

Claude Code·Codex 규칙의 원본이다. 루트의 `CLAUDE.md`·`AGENTS.md`와 전역 규칙 파일은 여기서 만든 생성 파일이므로 직접 고치지 않는다.

## 규칙을 고치는 법

1. `project/` 또는 `global/`의 파일을 고치거나 더한다
2. `sh agent-rules/build.sh`를 실행한다 (전역 파일까지면 `--global`)
3. 원본과 생성 파일을 함께 커밋한다

## 폴더 = 적용 범위

| 폴더 | 만들어지는 파일 |
|---|---|
| `project/` | 이 저장소 루트의 `CLAUDE.md`, `AGENTS.md` |
| `global/` | `$CLAUDE_CONFIG_DIR/CLAUDE.md` (기본 `~/.claude`), `$CODEX_HOME/AGENTS.md` (기본 `~/.codex`) |

## 파일 이름

- `NN-주제.md`: 숫자 순서대로 합친다. 10 단위로 띄워 두고 사이에 끼운다.
- 접미사로 대상 도구를 정한다. 접미사가 없으면 두 도구 모두, `*.claude.md`는 Claude Code만, `*.codex.md`는 Codex만이다.
- 파일 하나는 `## 제목` 섹션 하나로 시작한다.

## 전역 파일 보호

- `--global`은 첫 줄에 생성 표시(`<!-- 생성 파일`)가 없는 전역 파일을 덮어쓰지 않는다. 설치 도구가 쓴 파일일 수 있어서다. 내용을 `global/`로 옮긴 뒤 `--force`로 덮어쓴다.
- 전역 파일을 덮어쓸 때는 바뀌는 줄을 diff로 보여주고, 이전 파일을 `<파일>.prev`로 남긴다.

## 커밋 검사

`.githooks/pre-commit`은 `agent-rules/`·`CLAUDE.md`·`AGENTS.md`가 스테이징되면 아래 두 가지를 확인하고, 하나라도 어긋나면 커밋을 막는다.

- 이 세 경로에 스테이징하지 않은 변경이나 추적하지 않는 파일이 없다
- `build.sh --check`가 통과한다 (생성 파일 = 원본을 합친 결과)

## 왜 이렇게 했나

- Codex의 `AGENTS.md`는 다른 파일을 import하지 못한다. 그래서 원본을 합쳐서 만든다. Claude 쪽도 `@import` 대신 같은 방식으로 만들어 결과가 git diff에 보이게 한다.
- 원본을 `.claude/rules/`에 두지 않는다. Claude Code가 이 폴더를 자동으로 읽어서 규칙이 두 번 들어가고 `*.codex.md`도 Claude에 들어간다.
- `.ai/`는 relay 플러그인이 쓰는 폴더라서 피한다.
- Codex는 `AGENTS.md`를 기본 32 KiB(`project_doc_max_bytes`)까지만 읽는다. 넘으면 `build.sh`가 경고한다.
- Claude Code의 ADHD 출력 규칙은 SessionStart 훅으로 들어온다. 그래서 `global/20-output-style.codex.md`는 Codex에만 넣는다.
