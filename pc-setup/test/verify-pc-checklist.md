# 검증 PC 체크리스트

이미 쓰던 집 PC(검증 PC)에서 `pc-setup/` 을 처음 검증할 때 따른다. 선언의 출발점 PC 에서는 `-Check` 만 돌리고, 새 PC 경로는 [vm-checklist.md](vm-checklist.md) 를 따른다.

## 이 문서를 읽는 Claude 세션에게

진행은 Claude 세션이 맡고, 보고 확인과 UAC 확인 창은 사람이 맡는다. 원격 접속 경로(SSH 서버 열기 등)는 열지 않는다.

- [ ] **일반 권한** 창에서 세션을 띄우고 명령을 실행한다(관리자 창이면 부트스트랩·셋업이 멈춘다).
- [ ] 사람 확인 없이 기존 파일·앱·설정을 지우지 않는다.
- [ ] `-Skip` 은 사람이 정한 항목만 넣는다.
- [ ] 막히면 스스로 넘겨짚지 말고 멈춘 뒤 사람에게 묻는다.
- [ ] 사람: 검증할 브랜치 이름을 세션에게 알려 준다.
- [ ] 아래 `<저장소>` 는 부트스트랩이 clone 하는 위치(`$HOME\anything`)다. 명령을 실행할 때 실제 경로로 바꿔 넣는다.

## 0. 사람: Claude Code 설치

- [ ] 사람: PowerShell 에서 공식 설치 방법으로 Claude Code 를 설치하고 `claude` 로그인까지 마친다. Git for Windows 가 아직 없고 설치·실행 중 `bash.exe`(`git-bash`)를 요구하면 Git for Windows 도 먼저 손으로 설치한다.
  ```powershell
  irm https://claude.ai/install.ps1 | iex
  ```
- [ ] 사람: 설치가 끝나면 **일반 권한** 터미널에서 Claude 세션을 열고 이 체크리스트를 건넨다.

> 참고: 손으로 설치한 Claude Code 는 셋업에서 이미 설치된 것으로 보이고, 첫 셋업에서 `~/.local/bin` 사용자 PATH 맨 앞 맞춤만 `바꿈` 으로 나올 수 있다.

## 1. 미리보기 보고

- [ ] `git` 과 `pwsh` (PowerShell 7)가 있는지 확인한다.
  ```powershell
  Get-Command git, pwsh -ErrorAction SilentlyContinue
  ```
- [ ] **Git 과 pwsh 7 이 있으면**: `<저장소>` 가 이미 있는지 확인한다.
  - 폴더가 이미 있으면 그 폴더의 현재 브랜치와 상태를 보고하고 사람에게 어떻게 할지 묻는다(부트스트랩은 `<저장소>` 가 있으면 clone 도 pull 도 하지 않고 그대로 쓴다).
  - 폴더가 없으면 검증할 브랜치를 clone 한 뒤 일반 권한으로 `setup.ps1 -Check` 를 실행해 `다름`·`할 일`·`확인 못 함` 목록을 뽑는다.
  ```powershell
  git clone -b <branch> https://github.com/hdmun/anything.git <저장소>
  pwsh <저장소>\pc-setup\setup.ps1 -Check
  ```
- [ ] **Git 또는 pwsh 7 이 없으면**: 검증할 브랜치의 선언 파일 4개(`windows-settings.psd1`·`apps.psd1`·`config-files.psd1`·`repo-tools.psd1`)를 raw URL 로 읽고, `winget list`·레지스트리·파일 확인으로 항목마다 현재 상태를 확인해 보고한다.
  ```powershell
  $base = 'https://raw.githubusercontent.com/hdmun/anything/<branch>/pc-setup'
  foreach ($f in 'windows-settings.psd1','apps.psd1','config-files.psd1','repo-tools.psd1') {
      "=== $f ==="
      irm "$base/$f"
  }
  winget list
  ```
- [ ] 3번 절의 셋업 전 정리 대상(`nvm-windows`, 단독 설치 `pnpm`, 로컬 `~/.gitconfig` 의 겹치는 섹션)이 있는지도 함께 확인한다.
- [ ] 아래 모양으로 사람에게 미리보기를 보고한다.
  - 단계별 `다름`·`할 일`·`확인 못 함` 항목 목록
  - 셋업 전 정리 대상 해당 여부
  - 예상 UAC 횟수: 부트스트랩(Git·pwsh 가운데 없는 것이 있으면 1회, 둘 다 있으면 0회) + 셋업 1회

## 2. 사람: 보고 확인

- [ ] 사람: 선언이 현재 PC 의 의도와 다르면 선언을 고치는 커밋을 검증 브랜치에 먼저 올리고 push 한 뒤, 1번부터 다시 확인한다.
- [ ] 사람: 이번 실행에서만 건너뛸 항목이 있으면 `-Skip <Id,...>` 목록을 정해 세션에게 알린다(같은 `-Skip` 을 재실행에도 그대로 넘긴다).
- [ ] 사람: 3번 절의 셋업 전 정리 대상 가운데 실제로 정리할 항목을 정해 세션에게 알린다.

## 3. 셋업 전 정리 (해당할 때만)

사람이 2번에서 확인한 항목만 실행한다.

- [ ] **`nvm-windows` 가 있으면**: `npm ls -g --depth=0` 결과를 기록한 뒤 `winget uninstall CoreyButler.NVMforWindows` 로 제거한다. 제거 뒤에도 `C:\nvm4w`, `%LOCALAPPDATA%\nvm`, 환경 변수 `NVM_HOME`·`NVM_SYMLINK` 가 남아 있으면 정리한다(이 뒤 부트스트랩·셋업에서 scoop `nvm` v2 와 Node 26 이 설치된다).
  ```powershell
  npm ls -g --depth=0
  winget uninstall CoreyButler.NVMforWindows
  ```
- [ ] **`pnpm` 단독 설치본이 있으면**(`%LOCALAPPDATA%\pnpm` 에 `pnpm.exe` 등이 있을 때): 실행 파일(`pnpm`, `pnpm.CMD`, `pnpx*`)과 `.tools` 만 지운다. `%LOCALAPPDATA%\pnpm` 폴더(`PNPM_HOME`) 자체는 남긴다(전역 패키지와 `store` 자리이며 `@openai/codex` 도 여기에 설치된다. 실행 파일을 지우는 이유: PATH 에 남은 단독 설치본이 winget `pnpm` 을 가릴 수 있다).
  ```powershell
  $pnpmHome = Join-Path $env:LOCALAPPDATA 'pnpm'
  Get-ChildItem -LiteralPath $pnpmHome -Force -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^(pnpm(\.cmd|\.exe)?|pnpx.*|\.tools)$' }
  # 사람이 확인한 뒤에만 삭제:
  # Remove-Item -LiteralPath ... -Recurse -Force
  ```
- [ ] **로컬 `~/.gitconfig` 에 저장소 [../config/gitconfig](../config/gitconfig) 와 겹치는 섹션(`[user]`·`[filter "lfs"]`·`[core]`)이 있으면**: 사람이 확인한 뒤 해당 섹션을 지운다(셋업에서 `GitInclude` 로 연결한다).
- [ ] **npm 전역 패키지는 지우지 않는다**: `%APPDATA%\npm` 은 그대로 둔다. `claude`·`codex` 가 두 벌이 될 수 있지만 `apps/claude-code.ps1` 이 `~/.local/bin` 을 사용자 PATH 맨 앞에 넣어 새 판이 먼저 실행된다.

## 4. 부트스트랩

- [ ] **일반 권한** Windows PowerShell 5.1 창에서 검증할 브랜치의 raw URL 로 부트스트랩을 실행하고, 정보 스트림(`Write-Host`)을 포함한 출력 전체(`*>&1`)를 로그 파일로 남긴다(7번 결과 기록에 쓴다). 브랜치·`-Skip` 호출 모양은 [../bootstrap.ps1](../bootstrap.ps1) 이 정한 형식을 그대로 쓰며, `-Skip` 은 2번에서 사람이 정한 항목만 넣는다.
  `main` 브랜치이고 `-Skip` 이 없을 때:
  ```powershell
  & { irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex } *>&1 | Tee-Object -FilePath "$env:TEMP\pc-setup-bootstrap.log"
  ```
  그 밖의 경우(다른 브랜치이거나, `main` 에서 `-Skip` 을 넘길 때 — `main` 이면 `<branch>` 자리에 `main`):
  ```powershell
  & { & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hdmun/anything/<branch>/pc-setup/bootstrap.ps1))) -Branch <branch> [-Skip <Id1>,<Id2>] } *>&1 | Tee-Object -FilePath "$env:TEMP\pc-setup-bootstrap.log"
  ```
- [ ] 사람: UAC 확인 창이 뜰 때마다 승인하고, 실제로 뜬 횟수를 세어 세션에게 알린다.

## 5. 재부팅과 셋업 다시 실행

- [ ] 끝 요약에 `할 일: 재부팅 후 부트스트랩 다시 실행` 또는 `할 일: 재부팅 후 셋업 다시 실행` 이 있으면 사람에게 재부팅을 부탁한다.
- [ ] 사람: PC 를 재부팅한 뒤 **일반 권한** 터미널에서 Claude 세션을 다시 열고, 이 체크리스트의 5번부터 이어 가라고 알린다.
- [ ] 재부팅 뒤 `<저장소>\pc-setup\setup.ps1` 이 아직 없으면(부트스트랩이 저장소 clone 전에 재부팅으로 끝난 경우) 2번에서 정한 같은 `-Skip` 을 유지해 4번의 부트스트랩 명령을 일반 권한 Windows PowerShell 5.1 창에서 다시 실행한다.
- [ ] `<저장소>\pc-setup\setup.ps1` 이 있으면 일반 권한으로 `pwsh <저장소>\pc-setup\setup.ps1` 을 다시 실행하고 출력 전체(`*>&1`)를 로그 파일로 남긴다(2번에서 정한 `-Skip` 이 있으면 같은 `-Skip` 을 넘긴다). `할 일` 이 없어질 때까지 되풀이하고 재부팅 횟수를 적는다.
  ```powershell
  pwsh <저장소>\pc-setup\setup.ps1 *>&1 | Tee-Object -FilePath "$env:TEMP\pc-setup-rerun.log"
  # -Skip 이 있을 때:
  pwsh <저장소>\pc-setup\setup.ps1 -Skip <Id1>,<Id2> *>&1 | Tee-Object -FilePath "$env:TEMP\pc-setup-rerun.log"
  ```
- [ ] 사람: UAC 확인 창이 뜰 때마다 승인하고 실제 UAC 횟수를 센다.

## 6. 재실행 (멱등)

- [ ] **일반 권한** 창에서 셋업을 한 번 더 실행하고 출력 전체(`*>&1`)를 로그 파일로 남긴다(같은 `-Skip` 유지).
  ```powershell
  pwsh <저장소>\pc-setup\setup.ps1 *>&1 | Tee-Object -FilePath "$env:TEMP\pc-setup-idempotent.log"
  # -Skip 이 있을 때:
  pwsh <저장소>\pc-setup\setup.ps1 -Skip <Id1>,<Id2> *>&1 | Tee-Object -FilePath "$env:TEMP\pc-setup-idempotent.log"
  ```
- [ ] 사람: UAC 확인 창을 승인하고 실제 횟수를 센다.
- [ ] 끝 요약의 `바꿈`·`실패` 가 0개이고 UAC 가 1회인지 확인한다. 아니면 결과를 그대로 기록하고 사람에게 알린다.

## 7. 결과 기록

- [ ] 아래 항목을 담아 검증 요약을 만든다. **이 PC 의 개인값(IP·PC 이름·토큰)은 넣지 않는다(공개 저장소).**
  - 브랜치·커밋 (`git -C <저장소> rev-parse --abbrev-ref HEAD`, `git -C <저장소> rev-parse --short HEAD`)
  - 1번 미리보기 보고
  - 3번 셋업 전 정리에서 한 일
  - 단계별 끝 요약(부트스트랩·셋업 첫 실행·재실행 로그에서 붙여 넣기)
  - 승격 요청 횟수(부트스트랩·셋업 첫 실행·재실행)와 실제 UAC 횟수
  - 재부팅 횟수
  - 걸린 시간
  - 문제와 처리
- [ ] `gh auth status` 를 확인해 로그인돼 있으면 해당 구현 이슈의 PR 에 `gh pr comment` 로 직접 올린다. 로그인돼 있지 않으면 요약을 사람에게 건넨다.
  ```powershell
  gh auth status
  ```
- [ ] 사람(`gh` 미로그인일 때): 세션이 만든 요약을 해당 구현 이슈의 PR 댓글로 붙여 넣는다.
