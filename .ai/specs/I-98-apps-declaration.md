> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/98
> updatedAt: 2026-11-16T10:20:23Z

# 앱 선언 apps.psd1 에 패키지 관리자 원천 앱 38개를 쓰고 앱 단계를 셋업에 등록한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. 부모 이슈 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)의 앞 태스크들이 앱 단계(`lib/Apps.psm1` 의 `Get-AppItems`)와 원천별 처리(winget·scoop·nvm·pnpm·go)를 만들었다. 아직 실제 선언 `pc-setup/apps.psd1` 이 없고, 앱 단계가 셋업 단계 목록(`lib/Setup.psm1` 의 `$script:DefaultStageProviders`)에 없다.

이 태스크는 선언을 쓰고 단계를 등록한다.

- 넣을 앱은 [앱 목록 선별하기](https://github.com/hdmun/anything/issues/43) 의 넣음 목록이다. 그 뒤 결정으로 바뀐 것을 반영한다: lazygit·CMake·DBeaver·nano 는 scoop([결론 댓글](https://github.com/hdmun/anything/issues/43#issuecomment-6704619964)), nvm 은 winget `CoreyButler.NVMforWindows` 대신 scoop `nvm` v2 + Node 26 줄([런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62)), pnpm 은 winget `pnpm.pnpm`([앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44)), 전역 패키지 codex·gopls·staticcheck([런타임 전역 패키지 선언 정하기](https://github.com/hdmun/anything/issues/67)).
- 공식 배포 앱 9개(WSL·Ubuntu 24.04·RaiDrive·D2Coding·agy·NVIDIA 드라이버 확인·Flutter·claude-code·Pester)는 4번 구현 이슈 [pc-setup 앱: 공식 배포 9개](https://github.com/hdmun/anything/issues/99)가 더한다. 이 태스크에서는 넣지 않는다(winget `Microsoft.WSL`·`Canonical.Ubuntu.2404`·`OpenBoxLab.RaiDrive` 도 넣지 않는다).
- winget 항목의 `Scope` 는 이 PC 의 설치 위치(HKLM/HKCU)로 채운다(#44 「항목 키」). 아래 표는 2026-11-11 에 이 PC 의 언인스톨 레지스트리와 `winget list --scope` 로 확인한 값이다.
- 목록 순서가 설치 순서다. 승격 단계는 `Elevated` 항목만 먼저 처리하므로, 순서는 같은 권한 안에서 의미가 있다: scoop `nvm` → `node` → winget `pnpm.pnpm` → `@openai/codex`, winget `GoLang.Go` → go 항목.

## 범위 밖 (건드리지 말 것)

- 공식 배포 앱 줄과 `pc-setup/apps/*.ps1`: 4번 구현 이슈.
- 이 PC 에서 고치는 실행. 이 PC 의 winget 판 lazygit·CMake·DBeaver·nvm v1 은 셋업이 지우지 않는다([선언에 없는 앱(드리프트) 처리 정하기](https://github.com/hdmun/anything/issues/65)).
- `Apps.psm1`·원천 모듈의 동작. 버그를 찾으면 `ask` 로 묻는다.

## 변경 대상 파일

- `pc-setup/apps.psd1` — 신규
- `pc-setup/lib/Setup.psm1` — 수정 (`$script:DefaultStageProviders` 에 앱 단계 추가)
- `pc-setup/tests/AppsDeclaration.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/Setup.psm1
$script:DefaultStageProviders = @(
    { param($Root) Get-WindowsSettingItems -Root $Root }
    { param($Root) Get-AppItems -Root $Root }
)
```

## 동작 명세

### 정상 경로

**`pc-setup/apps.psd1`** (1번 이슈 형식 `@{ Items = @( ... ) }`, 한 줄 한 앱, 이 순서). 묶음마다 주석 한 줄을 달고, 사람이 읽을 이름이 ID 로 드러나지 않는 줄(msstore 등)에는 줄 끝 주석으로 앱 이름을 적는다.

| # | 줄 | 근거 |
|---|---|---|
| 1 | `@{ Id = 'Git.Git'; Scope = 'machine' }` | HKLM |
| 2 | `@{ Id = 'Microsoft.PowerShell'; Scope = 'machine' }` | `C:\Program Files\PowerShell\7`, HKLM. `winget list --scope` 는 user 로 맞았지만 설치 위치를 따른다. 부트스트랩도 승격 단계에서 설치한다(#42) |
| 3 | `@{ Id = 'GitHub.GitLFS'; Scope = 'machine' }` | HKLM |
| 4 | `@{ Id = 'GitHub.cli'; Scope = 'machine' }` | HKLM |
| 5 | `@{ Id = 'Fork.Fork'; Scope = 'user' }` | HKCU |
| 6 | `@{ Id = 'TortoiseGit.TortoiseGit'; Scope = 'machine' }` | HKLM |
| 7 | `@{ Id = 'Microsoft.WindowsTerminal'; Scope = 'user' }` | MSIX(사용자 등록) |
| 8 | `@{ Id = 'Microsoft.VisualStudioCode'; Scope = 'user' }` | HKCU (User 설치판) |
| 9 | `@{ Id = 'Notepad++.Notepad++'; Scope = 'machine' }` | HKLM |
| 10 | `@{ Id = 'Microsoft.VisualStudio.Enterprise'; Scope = 'machine' }` | HKLM |
| 11 | `@{ Id = 'JetBrains.Rider'; Scope = 'machine' }` | HKLM |
| 12 | `@{ Id = 'Google.Antigravity'; Scope = 'user' }` | HKCU |
| 13 | `@{ Id = 'DBBrowserForSQLite.DBBrowserForSQLite'; Scope = 'machine' }` | HKLM |
| 14 | `@{ Id = 'qishibo.AnotherRedisDesktopManager'; Scope = 'machine' }` | HKLM |
| 15 | `@{ Id = 'StablyAI.Orca'; Scope = 'user' }` | HKCU |
| 16 | `@{ Id = '7zip.7zip'; Scope = 'machine' }` | HKLM |
| 17 | `@{ Id = 'voidtools.Everything'; Scope = 'machine' }` | HKLM |
| 18 | `@{ Id = 'Obsidian.Obsidian'; Scope = 'user' }` | HKCU |
| 19 | `@{ Id = 'Google.Chrome'; Scope = 'machine' }` | HKLM. 이 PC 는 직접 설치본이라 winget 이 알아보지 못한다(`-Check` 에서 `다름`) |
| 20 | `@{ Id = 'Discord.Discord'; Scope = 'user' }` | HKCU |
| 21 | `@{ Id = 'Google.AndroidStudio'; Scope = 'machine' }` | HKLM |
| 22 | `@{ Id = 'WinMerge.WinMerge'; Scope = 'machine' }` | HKLM |
| 23 | `@{ Id = 'Python.Python.3.13'; Scope = 'user'; Elevated = $true }` | HKCU, py 런처 때문에 승격(#62) |
| 24 | `@{ Id = 'RubyInstallerTeam.RubyWithDevKit.3.4'; Scope = 'user' }` | HKCU |
| 25 | `@{ Id = 'Oven-sh.Bun'; Scope = 'user' }` | HKCU(`~\.bun`). 이 PC 는 직접 설치본이라 winget 이 알아보지 못한다 |
| 26 | `@{ Id = 'GoLang.Go'; Scope = 'machine' }` | HKLM |
| 27 | `@{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }` | #67 |
| 28 | `@{ Id = 'honnef.co/go/tools/cmd/staticcheck'; Origin = 'go' }` | #67 |
| 29 | `@{ Id = 'XP8CBJ40XLBWKX'; WingetSource = 'msstore' }   # Docker Desktop` | #44 |
| 30 | `@{ Id = '9PKTQ5699M62'; WingetSource = 'msstore' }   # iCloud` | #44 |
| 31 | `@{ Id = 'lazygit'; Origin = 'scoop'; Bucket = 'extras' }` | #43 |
| 32 | `@{ Id = 'cmake'; Origin = 'scoop'; Bucket = 'main' }` | #43 |
| 33 | `@{ Id = 'dbeaver'; Origin = 'scoop'; Bucket = 'extras' }` | #43 |
| 34 | `@{ Id = 'nano'; Origin = 'scoop'; Bucket = 'main' }` | #43 |
| 35 | `@{ Id = 'nvm'; Origin = 'scoop'; Bucket = 'main' }` | #62 (nvm v2) |
| 36 | `@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }` | #62 |
| 37 | `@{ Id = 'pnpm.pnpm'; Scope = 'user' }` | #44. 이 PC 에는 winget 판이 없다(단독 설치본) |
| 38 | `@{ Id = '@openai/codex'; Origin = 'pnpm' }` | #67 |

winget 줄 26개 + `pnpm.pnpm` = 27, msstore 2, scoop 5, nvm 1, pnpm 1, go 2 → 38줄이다.

**단계 등록**: 위 시그니처대로 `Get-AppItems` 를 Windows 설정 다음에 둔다. `Setup.psm1` 이 `Apps.psm1` 을 불러온다.

### 이 PC 의 `-Check` 에서 예상되는 앱 결과

게이트가 이 PC 에서 `-Check` 를 돌린다. 앞 태스크들의 동작대로라면 앱 줄은 아래처럼 나오고 `실패` 는 없다. 다르게 나오면(특히 `실패`) 원인을 확인한다.

- `다름`: `Google.Chrome`·`Oven-sh.Bun`·`pnpm.pnpm`(winget 이 알아보지 못함·없음), `lazygit`·`dbeaver`(버킷 extras 없음), `cmake`·`nvm`(설치 안 됨), `node`(nvm v2 없음, 이 PC 는 v1), `@openai/codex`(설치 안 됨)
- `그대로`: 나머지(msstore 둘, `nano`, gopls·staticcheck 포함)
- winget 확인이 앱마다 1~3초 걸려 `-Check` 가 1~2분 길어진다.

### 엣지 케이스

`AppsDeclaration.Tests.ps1` 에 아래를 둔다. **열거하지 않은 경우는 범위 밖이다.**

- 저장소 `pc-setup/apps.psd1` 로 `Get-AppItems -Root <pc-setup>` 가 예외 없이 38개를 돌려준다.
- Id 순서가 위 표 순서와 같다.
- `Elevated` 인 항목이 정확히 `Scope = 'machine'` 인 16개와 `Python.Python.3.13` 이다.
- 의존 순서: `nvm` < `node` < `pnpm.pnpm` < `@openai/codex`, `GoLang.Go` < 두 go 항목.
- `Setup.psm1` 의 기본 단계가 둘이고, 두 번째가 앱 단계다(`InModuleScope Setup` 으로 `$script:DefaultStageProviders` 를 보거나, 가짜 `Root` 로 `Invoke-Setup -Check` 를 돌려 결과 줄의 단계 순서가 `Windows 설정` → `앱` 인지 본다. 이때 원천 함수는 Mock 한다).

### 에러 처리

- 해당 없음(선언과 등록만 바꾼다).

## 기존 코드 참조

- `pc-setup/windows-settings.psd1` — 선언 파일 모양과 주석 쓰는 법.
- `pc-setup/tests/WindowsSettings.Tests.ps1` — 실제 선언을 검사하는 테스트 모양.
- `pc-setup/lib/Apps.psm1` — 스키마(원천별 키 규칙).

## 인수 조건

- [ ] `pc-setup/apps.psd1` 이 위 표 38줄과 같다(순서·키·값).
- [ ] 엣지 케이스 목록이 각각 테스트로 있다.
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 Windows 설정 줄 다음에 앱 38줄을 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 표에 없는 앱을 더하거나 표의 앱을 빼는 것, `Scope` 를 바꾸는 것. 이 PC 에서 값이 다르게 보이면 `ask` 로 묻는다.
- 공식 배포 줄(`Origin = 'official'`)을 넣는 것.
- 이 PC 에서 고치는 실행을 돌리는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
