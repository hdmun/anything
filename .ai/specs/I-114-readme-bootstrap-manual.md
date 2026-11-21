> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/114
> updatedAt: 2026-11-15T08:58:43Z

# pc-setup README 에 부트스트랩 한 줄과 「손으로 할 일」 절을 쓴다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 도구다. 앞 구현 이슈들로 `bootstrap.ps1`(새 PC, Windows PowerShell 5.1 한 줄 실행), `setup.ps1`(셋업, `-Check`·`-Skip`), 선언 파일 넷(`windows-settings.psd1`·`apps.psd1`·`config-files.psd1`·`repo-tools.psd1`)이 생겼다. 아직 `pc-setup/README.md` 가 없다. 용어는 `pc-setup/CONTEXT.md` 다.

셋업이 하지 않기로 한 일(비밀값·에이전트 폴더 등)은 사람이 손으로 한다. 그 목록을 README 의 「손으로 할 일」 절에 둔다. 부트스트랩 한 줄 바로 아래라서, 사람이 다음 할 일을 이어서 본다([구현 이슈 나누는 단위 정하기](https://github.com/hdmun/anything/issues/66) 「수동 체크리스트 자리」).

## 범위 밖 (건드리지 말 것)

- `pc-setup/test/vm-checklist.md`, `pc-setup/test/verify-pc-checklist.md`: 앞 태스크들이 만들었다. README 는 링크만 건다.
- 다른 폴더의 README(agent-accounts·rdp-notify·relay 등). 링크만 건다.
- 셋업·부트스트랩 코드, 선언 파일.
- 저장소 루트 `README.md`.

## 변경 대상 파일

- `pc-setup/README.md` — 신규
- `pc-setup/tests/Docs.Tests.ps1` — 수정 (앞 태스크가 만든 파일에 README 테스트를 더한다)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.** README 의 `##` 제목과 순서:

```
# pc-setup
## 새 PC
## 손으로 할 일
## 이미 셋업한 PC
## 선언
## 검증
```

## 동작 명세

### 정상 경로

**`# pc-setup`**: 한 단락. 무엇을 맞추나(앱·설정 파일·Windows 설정·저장소 도구), 여러 번 돌려도 결과가 같다는 것, 선언에 없는 것은 보지도 알리지도 지우지도 않는다는 것. 용어집 `CONTEXT.md` 링크.

**`## 새 PC`**: 새로 설치한 Windows 11 의 **일반 권한** Windows PowerShell 창에서 실행할 한 줄.

```powershell
irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex
```

- UAC 가 부트스트랩 1회·셋업 1회 뜬다. 관리자 창에서 실행하면 멈춘다.
- 저장소는 `$HOME\anything` 에 받는다.
- `할 일: 재부팅 후 셋업 다시 실행` 이 나오면 재부팅하고 `pwsh $HOME\anything\pc-setup\setup.ps1` 을 다시 실행한다.
- 브랜치나 `-Skip` 을 넘길 때의 호출 모양은 `bootstrap.ps1` 이 정한 형식을 그대로 옮긴다(2번 구현 이슈 [pc-setup 부트스트랩과 Sandbox 하네스](https://github.com/hdmun/anything/issues/88)가 만든 `bootstrap.ps1` 의 도움말이나 주석을 읽고 옮긴다).

**`## 손으로 할 일`**: 셋업이 끝난 뒤 사람이 하는 일의 체크리스트(`- [ ]`). 아래 항목을 이 순서의 소제목(`###`)으로 묶는다. 각 항목은 무엇을 하는지 한 줄과, 자세한 방법이 있는 문서 링크다. 값(키·토큰·호스트 이름)은 적지 않는다.

1. `### 비밀값`: SSH 키, `~/.ssh/config`(내용이 전부 개인값이라 저장소에 두지 않는다), 각종 토큰. `gh auth login`.
2. `### 작업 저장소`: 작업 저장소 clone.
3. `### 에이전트 폴더`: 셋업은 에이전트 폴더(Claude Code·Codex·agy 의 설정 폴더, agent-accounts 계정 폴더)를 건드리지 않는다([에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64)).
   - agent-accounts: `$PROFILE` 에 dot-source 한 줄을 넣는다 → `../agent-accounts/README.md`
   - 전역 규칙: Claude 설정 폴더마다 `sh agent-rules/build.sh --global`(`CLAUDE_CONFIG_DIR` 를 바꿔 가며) → `../agent-rules/` 의 README 또는 `build.sh` 도움말
   - relay 플러그인: 설정 폴더마다 마켓플레이스 추가와 설치 → `../plugins/relay/README.md`
   - codex `~/.codex/config.toml` 의 relay 사전 조건 키 두 개(`check_for_update_on_startup = false`, `[tui] terminal_title`) → `../plugins/relay/README.md` 에 적힌 값을 따른다고 쓴다(값을 README 에 다시 적지 않는다)
   - 그 밖의 내용(플러그인·스킬·`settings.json`·statusline·agy 폴더)은 그 PC 에서 손으로 맞춘다.
4. `### Flutter`: Android Studio 를 처음 실행해 Android SDK 를 설치하고 `flutter doctor --android-licenses` 를 실행한다([런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62)).
5. `### VS Code`: Settings Sync 에 로그인한다. 설정과 확장은 Settings Sync 가 맞춘다([설정 파일 관리 방식 정하기: symlink·복사](https://github.com/hdmun/anything/issues/45)).
6. `### 셋업이 알린 할 일`: 끝 요약의 `할 일:` 블록(예: rdp-notify env 파일, NVIDIA 드라이버)을 처리한다.

**`## 이미 셋업한 PC`**: `pwsh <저장소>\pc-setup\setup.ps1` 로 다시 맞춘다(UAC 1회). `-Check` 는 아무것도 바꾸지 않고 UAC 도 띄우지 않는다. `-Skip <Id,...>` 로 이번 실행에서만 항목을 건너뛴다. 결과 말 표(`그대로`·`바꿈`·`할 일`·`실패`·`다름`·`확인 못 함`·`건너뜀`)와 종료 코드(0·1·2). 업그레이드는 셋업 밖에서 한다(`winget upgrade`, `scoop update`, `pnpm update -g`, 앱 자체 업데이트).

**`## 선언`**: 선언 파일 넷과 각 파일이 담는 것, 항목 스크립트 폴더(`windows/`·`apps/`)를 표로. 선언에 앱을 더하거나 빼는 법 한두 줄(선언에서 빼도 PC 에서는 지워지지 않는다).

**`## 검증`**: 검증 표(Pester·이 PC `-Check`·VM `test/vm-checklist.md`)와 검증 PC(`test/verify-pc-checklist.md`) 한 줄씩, 각 문서 링크. Pester 6 이 필요하다(`apps/pester.ps1` 이 설치한다).

### 엣지 케이스

`Docs.Tests.ps1` 는 README 의 모양만 본다. 아래를 각각 테스트로 둔다.

- `pc-setup/README.md` 가 있고 `##` 제목이 「시그니처」의 다섯 개, 그 순서다.
- `## 새 PC` 절에 `irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex` 가 있다.
- `## 손으로 할 일` 절이 `## 새 PC` 바로 다음이고, `###` 소제목 6개가 위 순서다.
- README 의 상대 링크(`](` 뒤가 `http` 로 시작하지 않는 것, 앵커 `#…` 는 떼고 본다)가 가리키는 파일이 모두 있다. 이 태스크는 두 체크리스트 태스크 뒤에 진행되므로 `test/vm-checklist.md`·`test/verify-pc-checklist.md` 도 이미 있다. 예외를 두지 않는다.

### 에러 처리

해당 없음(문서).

## 기존 코드 참조

- `pc-setup/CONTEXT.md` — 용어. README 는 용어집의 말(선언·셋업·부트스트랩·원천·승격 단계·설정 파일·로컬 파일·Windows 설정·에이전트 폴더·검증 PC)을 그대로 쓴다.
- `pc-setup/bootstrap.ps1` — 인자와 호출 모양.
- `pc-setup/setup.ps1`, `pc-setup/lib/Report.psm1` — 인자, 결과 말, 종료 코드.
- `rdp-notify/README.md`, `agent-accounts/README.md` — 같은 저장소 README 의 문체.

## 인수 조건

- [ ] 「엣지 케이스」 테스트가 모두 있고 통과한다.
- [ ] README 에 실제 IP·PC 이름·이메일·토큰 같은 개인값이 없다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 다른 문서의 절차를 README 에 베껴 넣는 것(링크로 가리킨다).
- 셋업이 하는 일을 「손으로 할 일」에 넣는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
