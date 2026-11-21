# pc-setup

Windows 11 집 PC 를 **선언**대로(앱·설정 파일·Windows 설정·저장소 도구) 맞추는 **셋업** 도구다. 여러 번 돌려도 결과가 같고(멱등), 선언에 없는 것은 보지도 알리지도 지우지도 않는다. 용어는 [CONTEXT.md](CONTEXT.md) 를 따른다.

새 셋업: [SETUP.md](SETUP.md)

## 새 PC

새로 설치한 Windows 11 의 **일반 권한** Windows PowerShell 창에서 아래 한 줄을 실행한다.

```powershell
irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex
```

- UAC 확인 창은 **부트스트랩**에서 1회, **셋업**에서 1회 뜬다. 관리자 창에서 실행하면 멈춘다.
- 저장소는 `$HOME\anything` 에 받는다.
- 끝 요약에 `할 일: 재부팅 후 셋업 다시 실행` 이 나오면 재부팅한 뒤 일반 권한 창에서 다시 실행한다.

  ```powershell
  pwsh $HOME\anything\pc-setup\setup.ps1
  ```

- 다른 브랜치나 `-Skip` 을 넘길 때는 [bootstrap.ps1](bootstrap.ps1) 이 정한 형식을 쓴다.

  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hdmun/anything/<branch>/pc-setup/bootstrap.ps1))) -Branch <branch> -Skip <Id>,<Id>
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
- [ ] 전역 규칙: Claude 설정 폴더마다 `CLAUDE_CONFIG_DIR` 를 바꿔 가며 `sh agent-rules/build.sh --global` 을 실행한다 → [agent-rules/README.md](../agent-rules/README.md)
- [ ] relay 플러그인: 설정 폴더마다 마켓플레이스 추가와 설치를 실행한다 → [plugins/relay/README.md](../plugins/relay/README.md)
- [ ] Codex `~/.codex/config.toml`: relay 사전 조건 키 두 개(`check_for_update_on_startup = false`, `[tui] terminal_title`)는 [plugins/relay/README.md](../plugins/relay/README.md) 에 적힌 값을 따른다.
- [ ] 그 밖의 내용(플러그인·스킬·`settings.json`·statusline·agy 폴더)은 그 PC 에서 손으로 맞춘다.

### Flutter

- [ ] Android Studio 를 처음 실행해 Android SDK 를 설치하고 `flutter doctor --android-licenses` 를 실행한다([런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62)).

### VS Code

- [ ] Settings Sync 에 로그인해 설정과 확장을 맞춘다([설정 파일 관리 방식 정하기: symlink·복사](https://github.com/hdmun/anything/issues/45)).

### 셋업이 알린 할 일

- [ ] 끝 요약의 `할 일:` 블록(예: [rdp-notify/README.md](../rdp-notify/README.md) 의 env 파일 작성, NVIDIA 드라이버)을 처리한다.

## 이미 셋업한 PC

일반 권한 PowerShell 7 창에서 다시 맞춘다(UAC 1회).

```powershell
pwsh <저장소>\pc-setup\setup.ps1
```

- `-Check`: 아무것도 바꾸지 않고 UAC 도 띄우지 않는다.
- `-Skip <Id,...>`: 이번 실행에서만 지정한 항목을 건너뛴다.

| 결과 말 | 뜻 |
|---|---|
| `그대로` | 이미 선언과 같다 |
| `바꿈` | 선언대로 바꿨다 |
| `할 일` | 사람이 처리해야 할 일이 있다 |
| `실패` | 적용이나 확인에 실패했다 |
| `다름` | (`-Check`) 선언과 다르다 |
| `확인 못 함` | (`-Check`) 권한 등의 이유로 확인하지 못했다 |
| `건너뜀` | `-Skip` 으로 건너뛰었다 |

- 종료 코드: `0`(실패 0개), `1`(실패 1개 이상), `2`(실행 전 오류 — 관리자 창, 선언 오류, 모르는 `-Skip` Id).
- 앱 업그레이드는 셋업 밖에서 한다(`winget upgrade`, `scoop update`, `pnpm update -g`, 앱 자체 업데이트).

## 선언

| 파일 / 폴더 | 담는 것 |
|---|---|
| [windows-settings.psd1](windows-settings.psd1) | **Windows 설정** 목록 |
| [apps.psd1](apps.psd1) | **원천**별 앱·**런타임**·전역 도구 목록 |
| [config-files.psd1](config-files.psd1) | **설정 파일** 목록(링크·GitInclude) |
| [repo-tools.psd1](repo-tools.psd1) | **저장소 도구** 목록 |
| `windows/` | 스크립트형 Windows 설정 항목 |
| `apps/` | 공식 배포 앱 설치·확인 스크립트 |

선언에 앱을 더하려면 `apps.psd1` 의 `Items` 에 항목을 추가한다(공식 배포는 `apps/` 스크립트도 함께 둔다). 선언에서 항목을 빼도 이미 설치된 앱이나 설정은 PC 에서 지워지지 않는다.

## 검증

| 대상 | 방법 | 문서 |
|---|---|---|
| 단위 테스트 | `Invoke-Pester -Path pc-setup/tests -CI` (Pester 6 필요, `apps/pester.ps1` 이 설치) | — |
| 이 PC 상태 확인 | `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` | — |
| 새 PC 경로 (Hyper-V VM) | 빈 Windows 11 VM 에서 부트스트랩부터 검증 | [test/vm-checklist.md](test/vm-checklist.md) |

이미 쓰던 집 PC(**검증 PC**)에서 처음 검증할 때는 [test/verify-pc-checklist.md](test/verify-pc-checklist.md) 를 따른다.
