# agent-rules

Claude Code·Codex·Antigravity(`agy`)의 **사용자 전역** 규칙 원본이다. 특정 저장소에 의존하지 않는다. 아래 생성 파일은 여기서 만들므로 직접 고치지 않는다.

| 도구 | 생성 파일 |
|---|---|
| `claude` | `~/.claude/CLAUDE.md` |
| `codex` | `~/.codex/AGENTS.md` |
| `gemini` | `~/.gemini/GEMINI.md` |

- 대상은 이 3개로 고정이다. `CLAUDE_CONFIG_DIR`·`CODEX_HOME` 환경 변수는 보지 않는다.
- 대상 폴더(`~/.gemini` 등)가 없으면 그 도구가 설치되지 않은 PC 로 보고 건너뛴다. 폴더를 만들지 않는다.

## 규칙을 고치는 법

1. `global/` 의 파일을 고치거나 더한다
2. 원본을 커밋한다
3. 저장소 루트에서 `pwsh -NoProfile -File agent-rules/install.ps1` 을 실행한다 (먼저 보려면 `-Check`)

`install.ps1` 은 pc-setup 의 **저장소 도구**다([../pc-setup/repo-tools.md](../pc-setup/repo-tools.md)). 셋업이 `-Check` 와 맞춤 실행을 대신 부른다.

## 파일 이름

- `NN-주제[.도구...].md`: 파일 이름 서수(ordinal) 순서대로 합친다. 10 단위로 띄워 두고 사이에 끼운다.
- 마지막 `.md` 앞의 점 조각이 대상 도구다(`claude`·`codex`·`gemini`). 여러 개를 붙일 수 있다(예: `20-output-style.codex.gemini.md`). 도구 조각이 없으면 세 도구 모두에 들어간다.
- 도구 이름이 아닌 조각이 있으면 `실패: …` 를 출력하고 아무것도 쓰지 않는다.
- 파일 하나는 `## 제목` 섹션 하나로 시작한다.

생성 파일은 생성 표시 한 줄 뒤에 원본마다 빈 줄 하나와 원본 내용을 잇는다. UTF-8(BOM 없음), LF 줄바꿈이다.

## 생성 표시와 덮어쓰기

- 생성 파일 첫 줄은 `<!-- 생성 파일` 로 시작하는 생성 표시다. 원본 위치는 PC 경로가 아니라 저장소 기준(`hdmun/anything` 의 `agent-rules/global/`)으로 적는다.
- 첫 줄에 생성 표시가 없는 파일은 덮어쓰지 않고 `할 일: …` 을 출력한다. 손으로 쓴 규칙일 수 있어서다. 내용을 `global/` 로 옮긴 뒤 `-Force` 로 다시 실행한다.
  - 예외: 파일이 비어 있거나(공백만), 생성할 본문과 같으면(CR·앞뒤 공백 무시) 그냥 덮어쓴다.
- `-Force` 로 생성 표시가 없는 파일을 덮어쓸 때만 이전 파일을 `<파일>.prev` 로 남긴다. 생성 표시가 있는 파일은 백업 없이 덮어쓴다.
- `-Verbose` 이면 파일마다 결과 한 줄과 바뀌는 줄을 더 보여 준다. 표준 출력의 한 줄 약속은 그대로다.

## 출력

표준 출력은 한 줄이다. 셋업이 이 줄을 읽는다.

| 출력 | 뜻 |
|---|---|
| `그대로` | 모든 대상이 원본과 같다 |
| `다름 (CLAUDE.md, …)` | `-Check`: 다시 만들 파일이 있다 |
| `바꿈 (AGENTS.md, …)` | 그 파일을 다시 만들었다 |
| `할 일: …` | 생성 표시가 없는 파일이 있다 (위 절) |
| `실패: …` | 원본 이름이 틀렸거나 파일을 읽고 쓰지 못했다 |

여러 파일의 결과가 섞이면 `실패` > `할 일` > `다름`/`바꿈` > `그대로` 순서로 하나만 보인다. `실패`·`할 일` 은 첫 번째 해당 파일의 문장이다. `-Check` 는 아무것도 쓰지 않는다.

## 왜 이렇게 했나

- 파일은 제자리에서 덮어쓴다(임시 파일 교체·삭제 후 생성을 하지 않는다). agent-accounts 가 계정 폴더(`~/.claude-max` 등)의 `CLAUDE.md` 를 `~/.claude/CLAUDE.md` 를 가리키는 심볼릭 링크로 만들기 때문이다. 링크를 지우면 계정 폴더가 규칙을 잃는다.
- Codex 의 `AGENTS.md` 는 다른 파일을 import 하지 못한다. 그래서 원본을 합쳐서 만든다. 다른 도구도 같은 방식으로 만들어 결과를 한눈에 보게 한다.
- 원본을 `.claude/rules/` 에 두지 않는다. Claude Code 가 이 폴더를 자동으로 읽어서 규칙이 두 번 들어가고 `*.codex.md` 도 Claude 에 들어간다.
- Codex 는 `AGENTS.md` 를 기본 32 KiB(`project_doc_max_bytes`)까지만 읽는다. 넘으면 `-Verbose` 에서 경고한다.
- Claude Code 의 ADHD 출력 규칙은 SessionStart 훅으로 들어온다. 그래서 `global/20-output-style.codex.gemini.md` 는 Codex·agy 에만 넣는다.
- `agy` 는 `~/.gemini/GEMINI.md` 를 전역 규칙(`RULE[user_global]`)으로 읽는다. agy 1.5.14 의 변경 기록("global rules … `~/.gemini/GEMINI.md`")과 `agy -p` 실측으로 확인했다.
