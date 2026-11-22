# pc-setup

Windows 11 집 PC 를 **선언**대로(앱·설정 파일·Windows 설정·저장소 도구) 맞추는 **셋업** 도구다. 셋업은 에이전트 CLI(Claude Code·agy·Codex)가 [SETUP.md](SETUP.md) 를 읽고 진행한다. 여러 번 돌려도 결과가 같고(멱등), 선언에 없는 것은 보지도 알리지도 지우지도 않는다. 용어는 [CONTEXT.md](CONTEXT.md) 를 따른다.

## 새 PC

새로 설치한 Windows 11 의 **일반 권한** Windows PowerShell 창에서 아래 한 줄을 실행한다.

```powershell
irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex
```

- **부트스트랩**은 winget·Git·pwsh·에이전트 CLI 하나를 준비하고 저장소를 받는다. 이미 있는 것은 그대로 둔다.
- 부트스트랩은 UAC 를 띄우지 않는다. 셋업은 관리자 권한이 필요한 항목이 있을 때 최대 1회 띄운다. 관리자 창에서 실행하면 멈춘다.
- 저장소는 `$HOME\anything` 에 받는다.
- 에이전트는 기본이 `claude` 다. `-Agent agy` 나 `-Agent codex` 로 고를 수 있다(아래 브랜치 형식처럼 인자를 넘긴다).
- 부트스트랩은 끝에 두 줄을 출력한다. 사람이 그대로 쳐서 셋업을 시작한다.

  ```powershell
  cd $HOME\anything\pc-setup
  claude --dangerously-skip-permissions "SETUP.md 를 읽고 셋업해"
  ```

  두 번째 줄은 고른 에이전트의 자동 승인 플래그를 붙인 명령이다.
- 끝 요약에 `할 일: 재부팅 뒤 셋업을 다시 실행` 이 나오면 재부팅한 뒤 `pc-setup` 폴더에서 같은 에이전트 명령을 다시 실행한다.
- 다른 브랜치를 쓸 때는 [bootstrap.ps1](bootstrap.ps1) 이 정한 형식을 쓴다.

  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hdmun/anything/<branch>/pc-setup/bootstrap.ps1))) -Branch <branch>
  ```

## 손으로 할 일

셋업이 끝난 뒤 사람이 손으로 하는 일이다.

### 비밀값

- [ ] SSH 키와 `~/.ssh/config`(내용이 개인값이라 저장소에 두지 않는다), 각종 토큰을 챙겨 넣는다.
- [ ] `gh auth login` 으로 GitHub CLI 에 로그인한다.

### 작업 저장소

- [ ] 작업 저장소들을 clone 한다.

### 에이전트 폴더

셋업은 **에이전트 폴더**(Claude Code·Codex·agy 설정 폴더, agent-accounts 계정 폴더)를 건드리지 않는다([에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64)).

- [ ] agent-accounts: `$PROFILE` 에 dot-source 한 줄을 넣는다 → [agent-accounts/README.md](../agent-accounts/README.md)
- [ ] 전역 규칙: 셋업이 저장소 도구 `agent-rules` 로 맞춘다(에이전트 폴더 경계의 예외). 끝 요약에 `할 일` 이 나오면 그 파일 내용을 `agent-rules/global/` 로 옮긴 뒤 `pwsh -NoProfile -File agent-rules/install.ps1 -Force` 를 실행한다 → [agent-rules/README.md](../agent-rules/README.md)
- [ ] relay 플러그인: 설정 폴더마다 마켓플레이스 추가와 설치를 실행한다 → [plugins/relay/README.md](../plugins/relay/README.md)
- [ ] Codex `~/.codex/config.toml`: relay 사전 조건 키 두 개(`check_for_update_on_startup = false`, `[tui] terminal_title`)는 [plugins/relay/README.md](../plugins/relay/README.md) 에 적힌 값을 따른다.
- [ ] statusline: 셋업이 저장소 도구 `claude-statusline`·`agy-statusline`·`codex-statusline` 으로 맞춘다(에이전트 폴더 경계의 예외). Codex 는 처음 한 번 TUI 를 재시작해 상태 줄이 나오는지 본다 → [codex-statusline/README.md](../codex-statusline/README.md)
- [ ] 그 밖의 내용(플러그인·스킬·`settings.json` 의 나머지 키·agy 폴더)은 그 PC 에서 손으로 맞춘다.

### Flutter

- [ ] Android Studio 를 처음 실행해 Android SDK 를 설치하고 `flutter doctor --android-licenses` 를 실행한다([런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62)).

### VS Code

- [ ] Settings Sync 에 로그인해 설정과 확장을 맞춘다([설정 파일 관리 방식 정하기: symlink·복사](https://github.com/hdmun/anything/issues/45)).

### 셋업이 알린 할 일

- [ ] 셋업이 대화에 남긴 끝 요약의 `할 일` 항목(예: [rdp-notify/README.md](../rdp-notify/README.md) 의 env 파일 작성, NVIDIA 드라이버)을 처리한다.

## 이미 셋업한 PC

`<저장소>\pc-setup` 폴더에서 에이전트를 띄우고 `SETUP.md 를 읽고 셋업해` 라고 친다. 어느 권한 모드로 열어도 된다. 자동 승인 모드가 아니면 에이전트 도구가 명령마다 묻는다.

- 확인만 하려면 셋업이 보여 주는 **계획**에서 중단한다.

| 결과 말 | 뜻 |
|---|---|
| `그대로` | 이미 선언과 같다 |
| `바꿈` | 선언대로 바꿨다 |
| `할 일` | 사람이 처리해야 할 일이 있다 |
| `실패` | 적용이나 확인에 실패했다 |

- 앱 업그레이드는 셋업 밖에서 한다(`winget upgrade`, `scoop update`, `pnpm update -g`, 앱 자체 업데이트).

## 선언

| 파일 / 폴더 | 담는 것 |
|---|---|
| [windows-settings.md](windows-settings.md) | **Windows 설정** 목록 |
| [apps.md](apps.md) | **원천**별 앱·**런타임**·전역 도구 목록 |
| [config-files.md](config-files.md) | **설정 파일** 목록(링크·GitInclude) |
| [repo-tools.md](repo-tools.md) | **저장소 도구** 목록 |
| `tools/` | PATH 추가·설정 파일 연결 스크립트 |
| `config/` | 설정 파일 정본 |

선언에 앱을 더하려면 `apps.md` 표에 한 줄을 추가한다(URL·경로는 적지 않는다). 선언에서 항목을 빼도 이미 설치된 앱이나 설정은 PC 에서 지워지지 않는다.

## 검증

| 대상 | 방법 |
|---|---|
| 단위 테스트 | `Invoke-Pester -Path pc-setup/tests -CI` (Pester 는 `apps.md` 항목) |
| 멱등 확인 | 이미 셋업한 PC 에서 셋업을 두 번 돌리고, 두 번째 요약이 `바꿈` 0·`실패` 0 인지 본다 |
