> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/110
> updatedAt: 2026-11-11T11:47:49Z

# README 의 고정 저장소 경로를 <저장소> 로 바꾼다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 이 이슈의 부모는 [pc-setup 설정 파일과 저장소 도구](https://github.com/hdmun/anything/issues/105)이다.

이 저장소(`hdmun/anything`)는 PC 마다 다른 폴더에 있다. 지금 PC 는 `~/scripts` 에 있고, 새 PC 는 **부트스트랩**이 `$HOME\anything` 에 clone 한다. 셋업과 도구는 저장소 경로를 `$PSScriptRoot` 로 계산하므로 위치와 상관없이 돈다. 그런데 README 의 명령 예시는 `$env:USERPROFILE\scripts\…` 나 `C:\Users\<사용자>\scripts` 처럼 이 PC 의 경로를 박아 두었다. 결정에 따라 이 경로를 `<저장소>` 로 바꾼다([부트스트랩 진입점과 관리자 권한 처리 정하기](https://github.com/hdmun/anything/issues/42) 「clone 위치」: "README 에 적힌 `$env:USERPROFILE\scripts` 경로(agent-accounts·rdp-notify·relay)를 `<저장소>` 로 바꾼다").

셋업은 고치는 실행이 끝날 때 사용자 환경 변수 `ANYTHING_REPO` 에 저장소 경로를 남긴다(1번 구현 이슈). README 에서는 이 값을 `<저장소>` 의 설명으로만 쓴다.

2026-11-11 에 `grep` 으로 찾은 대상(줄 번호는 그날 main 기준):

| 파일 | 줄 | 지금 글 |
|---|---|---|
| `agent-accounts/README.md` | 14 | `Add-Content $PROFILE '. "$env:USERPROFILE\scripts\agent-accounts\AgentAccounts.ps1"'` |
| `agent-accounts/AgentAccounts.ps1` | 1 | 주석 `# $PROFILE 에서 dot-source 한다:  . "$env:USERPROFILE\scripts\agent-accounts\AgentAccounts.ps1"` |
| `rdp-notify/README.md` | 21, 30, 100 | `cd "$env:USERPROFILE\scripts\rdp-notify"` |
| `rdp-notify/README.md` | 60 | `-File "$env:USERPROFILE\scripts\rdp-notify\rdp-notify.ps1"` |
| `rdp-notify/README.md` | 70 | `Get-Content "$env:USERPROFILE\scripts\rdp-notify\logs\…"` |
| `rdp-notify/README.md` | 82 | 「문제 해결」 표의 `'\scripts\...' 토큰`·`$env:USERPROFILE\...` 행 |
| `plugins/relay/README.md` | 37 | `claude plugin marketplace add C:\Users\<사용자>\scripts` |
| `plugins/relay/README.md` | 314, 354 | `smoke --dir C:/Users/<사용자>/scripts` |
| `plugins/relay/README.md` | 366, 369 | 마켓플레이스 소스 폴더 설명과 `git -C C:/Users/<사용자>/scripts …` |
| `synology/README.md` | 37, 91, 159 | `cd "$env:USERPROFILE\scripts\synology"` |

`synology/README.md` 는 결정 문구의 목록에 없지만 같은 고정 경로라 함께 바꾼다.

## 범위 밖 (건드리지 말 것)

- `plugins/relay/docs/plan.md` 같은 지난 기록 문서, `plugins/relay/tests/fixtures/` 의 JSON(실측 기록이다).
- 경로 말고 다른 README 내용(설치 순서, 셋업 안내 추가 등).
- `agent-accounts/AgentAccounts.ps1` 의 1줄 주석 밖의 코드.
- `plugins/relay/.claude-plugin/plugin.json` 버전, relay 역할 파일.

## 변경 대상 파일

- `agent-accounts/README.md` — 수정
- `agent-accounts/AgentAccounts.ps1` — 수정 (1줄 주석만)
- `rdp-notify/README.md` — 수정
- `plugins/relay/README.md` — 수정
- `synology/README.md` — 수정
- `pc-setup/tests/RepoPaths.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

각 README 에서 `<저장소>` 를 처음 쓰는 곳 바로 앞(또는 그 절 첫머리)에 이 문장을 한 번 넣는다.

```
`<저장소>` 는 이 저장소를 받은 폴더다(새 PC 는 `$HOME\anything`). 셋업을 돌린 PC 에서는 환경 변수 `ANYTHING_REPO` 에 이 경로가 들어 있다.
```

## 동작 명세

### 정상 경로

- PowerShell 명령의 `"$env:USERPROFILE\scripts\<폴더>…"` 는 `"<저장소>\<폴더>…"` 로 바꾼다. 예: `cd "<저장소>\rdp-notify"`, `Add-Content $PROFILE '. "<저장소>\agent-accounts\AgentAccounts.ps1"'`.
- relay README 의 `C:\Users\<사용자>\scripts`·`C:/Users/<사용자>/scripts` 는 `<저장소>` 로 바꾼다. 예: `claude plugin marketplace add <저장소>`, `smoke --dir <저장소> --agent codex`, `git -C <저장소> branch --show-current`.
- `agent-accounts/AgentAccounts.ps1` 1줄 주석도 `. "<저장소>\agent-accounts\AgentAccounts.ps1"` 로 바꾼다.
- `rdp-notify/README.md` 82번 줄 「문제 해결」 행은 경로를 따옴표 없이 입력한 경우의 안내다. 행의 뜻은 유지하고, 그 안의 고정 경로 글(`'\scripts\...'`, `$env:USERPROFILE\...`)만 `<저장소>` 를 쓰는 글로 바꾼다.
- 바꾼 뒤 위 표의 파일에 `USERPROFILE\scripts` 와 `<드라이브>:\Users\<누구>\scripts` 모양이 남지 않는다.

### 엣지 케이스

`pc-setup/tests/RepoPaths.Tests.ps1` 에 아래를 테스트로 둔다. 대상 파일 목록은 위 표의 다섯 파일이다.

- 각 파일에 `USERPROFILE\scripts`(대소문자 무시)가 없다.
- 각 파일에 정규식 `[A-Za-z]:[\\/]Users[\\/][^\\/\s]+[\\/]scripts` 가 없다.
- README 네 개에 `<저장소>` 와 시그니처의 설명 문장이 있다.

**열거하지 않은 경우는 범위 밖이다**(예: 다른 문서의 경로, `~/scripts` 를 말로 언급하는 문장).

### 에러 처리

- 없음(문서 수정).

## 기존 코드 참조

- `rdp-notify/README.md` 「설치」·「미리 보기」·「로그」·「제거」 — 바꿀 명령들.
- `plugins/relay/README.md` 「설치」·「3.0.0 으로 올리기」 — 바꿀 명령들.
- `rdp-notify/*.ps1` 은 UTF-8 BOM 포함으로 저장한다는 규칙(`rdp-notify/README.md` 「바꿀 때」). `agent-accounts/AgentAccounts.ps1` 은 고치기 전 인코딩(BOM 여부)을 그대로 유지한다.
- `plugins/relay/` 아래 파일을 바꾸면 커밋 때 `.githooks/pre-commit` 이 relay 단위 테스트를 돌린다.

## 인수 조건

- [ ] 표의 모든 줄이 `<저장소>` 로 바뀌었고, 엣지 케이스 테스트가 있다.
- [ ] `python -m unittest discover -s plugins/relay/tests -q` 가 통과한다(relay README 를 바꿨으므로).
- [ ] `agent-accounts/AgentAccounts.ps1` 은 1줄 주석만 바뀌었고 인코딩이 그대로다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 경로를 `$env:ANYTHING_REPO` 로 바꾸는 것(셋업을 돌리지 않은 PC 에는 없다. 결정은 `<저장소>` 다).
- 지난 기록 문서(`docs/plan.md` 등)와 테스트 픽스처를 고치는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
