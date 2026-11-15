> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/89
> updatedAt: 2026-11-14T00:59:08Z

# 부트스트랩(bootstrap.ps1)으로 winget·Git·pwsh 를 갖추고 저장소를 받아 셋업으로 넘긴다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)이 `pc-setup/setup.ps1`(pwsh 7 전용)을 만들었다. 설계는 그 이슈의 「공통 설계」를 따른다. 이 태스크는 그 앞 단계인 **부트스트랩** `pc-setup/bootstrap.ps1` 을 만든다. 부트스트랩은 아무것도 없는 Windows 에서 저장소를 받아 셋업을 처음 실행하기까지의 과정이다.

정한 것([부트스트랩 진입점과 관리자 권한 처리 정하기](https://github.com/hdmun/anything/issues/42) 「진입점」·「부트스트랩」, [집의 다른 PC 로 셋업을 검증하는 방식 정하기](https://github.com/hdmun/anything/issues/71) 「승격 요청 횟수」, [셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「셋업·부트스트랩에 더하는 것」):

- 새 PC 의 Windows PowerShell 5.1 에서 `irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex` 로 실행한다. 새 Windows 의 실행 정책은 `Restricted` 지만 `iex` 는 실행 정책에 걸리지 않는다. 실행 정책은 바꾸지 않는다.
- 순서: 관리자 창이면 멈춤 → 저장소 위치 결정(`ANYTHING_REPO`) → winget 보장 → Git·pwsh 보장(**승격 단계**, 둘 다 있으면 UAC 0회) → 일반 권한으로 clone → pwsh 로 셋업.
- winget 보장에 PSGallery(`Repair-WinGetPackageManager`)는 쓰지 않는다.
- 셋업과 같은 Id(`Git.Git`·`Microsoft.PowerShell`)를 앱 선언에도 둔다(3번 구현 이슈). 그래서 셋업에서는 `그대로` 로 나온다.
- 끝 요약에 부트스트랩의 **승격 요청 횟수**를 찍는다. 새 PC 는 부트스트랩 1 + 셋업 1 = 2회다.
- 인자 `-Source`(기본 GitHub URL, git bundle 경로도 받음)·`-Branch`·`-Skip`. `-Skip` 은 셋업으로 넘긴다. Sandbox 하네스(뒤 태스크)는 `-Source <bundle>` 로 부른다.

이 PC 에서 확인한 사실(2026-11-11 이 PC 확인): Windows PowerShell 5.1 은 `C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe`, winget `v1.29.380`(`Microsoft.DesktopAppInstaller_8wekyb3d8bbwe` 1.29.380.0), git `2.47.0.windows.2`. `git clone <HEAD 만 담은 bundle> <폴더>` 는 detached HEAD 로 받아진다. Windows Sandbox 에는 winget·git·pwsh·DesktopAppInstaller 가 없다([셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「확인한 사실」).

Windows PowerShell 5.1 의 제약: 파일을 `-File` 로 읽을 때 BOM 없는 UTF-8 은 ANSI(cp949)로 읽혀 한국어가 깨지거나 파싱이 실패한다. `??`·삼항 연산자·`-Parallel`·`Join-Path` 의 3개 이상 인자 같은 pwsh 7 문법은 쓸 수 없다.

Pester 6.2.0 이 이 PC 에 설치돼 있다(pwsh 7 쪽 모듈 경로). Pester 는 pwsh 7 에서 돈다. 5.1 호환은 5.1 파서 검사로 본다. 실제 동작은 Sandbox(사람이 할 일)가 본다.

## 범위 밖 (건드리지 말 것)

- `pc-setup/setup.ps1`·`pc-setup/lib/*`: 1번 구현 이슈의 것. 버그를 찾으면 `ask` 로 묻는다.
- Sandbox 하네스(`pc-setup/test/*`): 뒤 태스크.
- 앱 선언(`apps.psd1`): 3번 구현 이슈.
- 실행 정책 변경, 저장소 pull·업데이트, 재부팅.
- `README.md` 의 부트스트랩 안내: 6번 구현 이슈.

## 변경 대상 파일

- `pc-setup/bootstrap.ps1` — 신규 (**ASCII 전용**, BOM 없음)
- `pc-setup/tests/Bootstrap.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/bootstrap.ps1 — Windows PowerShell 5.1 (pwsh 7 에서도 파싱된다)
[CmdletBinding()]
param(
    [string]$Source = 'https://github.com/hdmun/anything.git',   # git URL 또는 git bundle 파일 경로
    [string]$Branch = '',                # 빈 값이면 Source 의 기본 브랜치(HEAD)를 받는다
    [string[]]$Skip = @(),               # 셋업으로 넘긴다
    [string]$ResultPath = '',            # 부트스트랩 자신의 결과 JSON
    [string]$SetupResultPath = ''        # 셋업에 -ResultPath 로 넘긴다
)

# 스크립트 안 함수 (테스트가 이 이름으로 Mock 한다)
function Test-AdminWindow { }                                   # → [bool]
function Get-AnythingRepo { }                                   # → 사용자 환경 변수 ANYTHING_REPO 값([Environment]::GetEnvironmentVariable(..., 'User')) 또는 ''
function Get-DefaultRepoPath { }                                # → "$HOME\anything"
function Invoke-Winget { param([string[]]$Arguments) }          # winget 을 부르고 종료 코드를 돌려준다
function Get-WingetVersion { }                                  # → [version] 또는 $null(없음)
function Install-WingetFromGitHub { }                           # GitHub winget-cli 최신 릴리스의 msixbundle 과 의존성을 Add-AppxPackage. 실패하면 예외
function Register-WingetFamily { }                              # Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe. 실패하면 예외
function Invoke-ElevatedInstall { param([string[]]$Ids) }       # 승격된 powershell.exe 하나로 Ids 를 winget 설치 → @{ Requested = 1; Codes = @{ <Id> = <종료 코드> }; Error = '' | '승격 거부됨' | '승격 단계 결과 없음' }
function Invoke-Git { param([string[]]$Arguments) }             # git 을 부르고 종료 코드를 돌려준다
function Update-SessionPath { }                                 # 현재 세션 PATH 를 Machine + User 레지스트리 값으로 다시 읽는다
function Start-SetupScript { param([string]$RepoPath, [string[]]$Skip, [string]$ResultPath) }   # pwsh -NoProfile -File <repo>\pc-setup\setup.ps1 ... → 종료 코드
function Invoke-Bootstrap { param([string]$Source, [string]$Branch, [string[]]$Skip, [string]$ResultPath, [string]$SetupResultPath) }   # → 종료 코드 [int]

# 맨 아래 본문 (이 두 줄만)
$code = Invoke-Bootstrap -Source $Source -Branch $Branch -Skip $Skip -ResultPath $ResultPath -SetupResultPath $SetupResultPath
if ($PSCommandPath) { exit $code } else { $global:LASTEXITCODE = $code }
```

`irm | iex`·스크립트 블록으로 실행될 때는 `$PSCommandPath` 가 비어 있다. 그때 `exit` 를 부르면 사용자의 PowerShell 창이 닫히므로 `exit` 는 파일로 실행될 때만 부른다.

부트스트랩 결과 JSON(`-ResultPath`) 모양은 셋업과 같다(UTF-8):

```json
{ "Check": false, "ElevationRequests": 1, "DurationSeconds": 95.2,
  "Results": [ { "Stage": "부트스트랩", "Id": "winget", "Status": "바꿈", "Detail": "" } ] }
```

## 동작 명세

### 정상 경로

**호출 모양** (README 는 6번 구현 이슈가 쓴다. 이 태스크는 스크립트 맨 위 주석에 두 줄을 적는다)

```powershell
# 기본 (main 브랜치, 인자 없음)
irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex
# 인자가 필요할 때 (push 된 브랜치 검증 등)
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/hdmun/anything/<브랜치>/pc-setup/bootstrap.ps1))) -Branch <브랜치> -Skip <Id>,<Id>
```

raw URL 의 브랜치는 내려받을 스크립트만 정한다. clone 할 브랜치는 `-Branch` 가 정한다.

**`Invoke-Bootstrap`** 결과 줄은 `[부트스트랩] <Id>: <결과>` 모양이고 항목이 끝날 때마다 `Write-Host` 로 출력한다. 결과 Id 는 `winget`·`Git.Git`·`Microsoft.PowerShell`·`clone` 넷이다.

1. **관리자 창**: `Test-AdminWindow` 가 `$true` 면 `부트스트랩은 일반 권한 창에서 실행한다` 를 출력하고 2 를 돌려준다.
2. **저장소 위치**: `Get-AnythingRepo` 값이 있고 `<값>\pc-setup\setup.ps1` 이 있으면 그 폴더를 저장소로 쓰고 clone 하지 않는다. 아니면 `Get-DefaultRepoPath`(`$HOME\anything`)다. 아래 3·4 단계는 이 경우에도 돈다(이미 있으면 아무것도 하지 않는다).
3. **winget 보장**: `Get-WingetVersion` 이 최소 버전 이상이면 `winget: 그대로`. 아니면 `Register-WingetFamily` → `Update-SessionPath` → 다시 확인 → 아직 아니면 `Install-WingetFromGitHub` → `Update-SessionPath` → 다시 확인. 보장되면 `winget: 바꿈`, 끝내 안 되면 `winget: 실패: <마지막 오류>` 를 내고 1 을 돌려준다.
   - 최소 버전은 스크립트 맨 위 상수 하나(`$MinWingetVersion`)다. 값은 셋업이 쓰는 `winget install --no-upgrade` 를 지원하는 가장 낮은 버전 이상으로 구현자가 winget-cli 릴리스 노트에서 확인해 정하고, 근거(릴리스 이름)를 주석에 적는다.
   - `Install-WingetFromGitHub`: `https://api.github.com/repos/microsoft/winget-cli/releases/latest` 에서 msixbundle 과 의존성 묶음 자산을 `$env:TEMP` 에 받고, 의존성(현재 아키텍처 폴더의 `.appx`)을 먼저, msixbundle 을 나중에 `Add-AppxPackage` 한다. 일반 권한(사용자 범위)이다. 자산 이름은 구현자가 실제 릴리스에서 확인한다.
4. **Git·pwsh 보장**: `Git.Git`·`Microsoft.PowerShell` 각각을 일반 권한으로 `Invoke-Winget list --id <Id> -e --accept-source-agreements` 의 종료 코드(0 = 있음)로 확인한다.
   - 둘 다 있으면 둘 다 `그대로`, 승격 요청 0회.
   - 없는 것이 있으면 `Invoke-ElevatedInstall -Ids <없는 것만>` 을 한 번 부른다(승격 요청 1회). 종료 코드 0 → `바꿈`, `0x8A150109`(재부팅 필요) → `할 일: 재부팅 후 부트스트랩 다시 실행`, 그 밖 → `실패: winget 종료 코드 0x<8자리 16진수>`. `Error` 가 있으면 그 Id 들은 `실패: <Error>`. 있던 것은 `그대로`.
   - `실패`·`할 일` 이 하나라도 있으면 요약을 출력하고 1(실패) 또는 0(할 일만)을 돌려준다. 셋업으로 넘어가지 않는다.
   - 성공하면 `Update-SessionPath` 를 부른다.
5. **clone**: 2 에서 정한 폴더가 이미 있으면 clone 도 pull 도 하지 않는다. `<폴더>\pc-setup\setup.ps1` 이 있으면 `clone: 그대로`, 없으면 `clone: 실패: <폴더> 에 셋업이 없다` 와 1. 폴더가 없으면 `Invoke-Git clone [-b <Branch>] <Source> <폴더>` 를 일반 권한으로 부른다. 0 이면 `clone: 바꿈`, 아니면 `clone: 실패: git clone 종료 코드 <n>` 과 1.
6. **요약**: `부트스트랩 승격 요청: <n>회`, `부트스트랩 걸린 시간: mm:ss` 를 출력한다. `-ResultPath` 가 있으면 JSON 을 쓴다(4·5 에서 멈출 때도 쓴다).
7. **셋업**: `Start-SetupScript -RepoPath <폴더> -Skip $Skip -ResultPath $SetupResultPath` 의 종료 코드를 그대로 돌려준다. `Start-SetupScript` 는 `pwsh` 를 `Get-Command pwsh` 로 찾고, 없으면 `$env:ProgramFiles\PowerShell\7\pwsh.exe` 를 쓴다. `-Skip` 이 비어 있지 않으면 `-Skip (<Id 를 쉼표로 이은 문자열>)` 를, `ResultPath` 가 있으면 `-ResultPath <경로>` 를 붙인다.

**`Invoke-ElevatedInstall`**: 결과 파일 `$env:TEMP\pc-setup-bootstrap-<GUID>.json` 을 정한다. Id 마다 `winget install --id <Id> -e --scope machine --no-upgrade --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity` 를 차례로 실행하고 종료 코드를 모아 결과 파일에 쓰는 스크립트 문자열을 만든다. 그 문자열을 `-EncodedCommand`(UTF-16LE Base64)로 `Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',<b64>` 에 넘긴다. 부트스트랩이 `iex` 로 돌 때는 파일 경로가 없으므로 자기 파일을 승격해 다시 부르는 방식은 쓰지 않는다. UAC 거절(`Start-Process` 예외) → `Error = '승격 거부됨'`. 결과 파일이 없거나 JSON 이 아니면 `Error = '승격 단계 결과 없음'`. 읽은 뒤 결과 파일을 지운다.

**파일 인코딩**: `bootstrap.ps1` 은 BOM 없이 ASCII 바이트(0x00~0x7F)만으로 쓴다. 근거(2026-11-14 구현자 확인): 5.1 의 `irm` 은 BOM(U+FEFF)을 문자열 맨 앞에 남기고, 그러면 `irm | iex`·`[scriptblock]::Create((irm ...))` 모두 맨 위 `[CmdletBinding()] param(...)` 에서 ParserError 로 실패한다. ASCII 만 쓰면 5.1 이 `-File` 로 ANSI 로 읽어도 결과가 같아 BOM 이 필요 없다. 한국어 출력 문자열(예: `승격 거부됨`)은 값을 바꾸지 않고 `[char]` 코드(예: `-join ([char[]](0xC2B9,0xACA9))`)로 만든다. 문자열을 만드는 작은 도우미 함수 하나를 두어도 된다. 호출 모양(`irm ... | iex`)과 시그니처는 바꾸지 않는다.

### 엣지 케이스

테스트 방식: Pester(pwsh 7)에서 `[System.Management.Automation.Language.Parser]::ParseFile` 로 `bootstrap.ps1` 을 파싱해 **함수 정의만** 꺼내 정의한다(`FunctionDefinitionAst` 의 `Extent.Text` 를 스크립트 블록으로 만들어 dot-source). 맨 아래 본문은 돌리지 않는다. 그다음 바깥 명령 함수(`Test-AdminWindow`·`Get-AnythingRepo`·`Get-WingetVersion`·`Register-WingetFamily`·`Install-WingetFromGitHub`·`Invoke-Winget`·`Invoke-ElevatedInstall`·`Invoke-Git`·`Update-SessionPath`·`Start-SetupScript`)를 `Mock` 하고 `Invoke-Bootstrap` 을 부른다. 실제 winget·git·UAC 는 쓰지 않는다.

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 프록시 환경, ARM64 PC, 저장소 폴더가 git 저장소가 아닌 경우의 복구).

| # | 상황 | 기대 |
|---|---|---|
| 1 | 관리자 창 | 2, winget·git 함수 안 불림 |
| 2 | winget 충분·Git·pwsh 있음·`$HOME\anything` 없음 | winget 그대로, 둘 다 그대로, `Invoke-ElevatedInstall` 안 불림, clone 바꿈, 승격 0회, 셋업 종료 코드를 돌려줌 |
| 3 | winget 없음 → `Register-WingetFamily` 후 충분 | winget 바꿈, `Install-WingetFromGitHub` 안 불림 |
| 4 | 등록도 실패 → GitHub 설치 후 충분 | winget 바꿈 |
| 5 | GitHub 설치도 실패 | winget 실패, 1, 이후 단계 안 불림 |
| 6 | Git 없음·pwsh 있음 | `Invoke-ElevatedInstall -Ids Git.Git` 1번, 승격 1회 |
| 7 | 둘 다 없음 | `-Ids Git.Git,Microsoft.PowerShell` 로 1번(두 번 아님) |
| 8 | 설치 종료 코드 `0x8A150109` | `할 일: 재부팅 후 부트스트랩 다시 실행`, 셋업 안 불림, 0 |
| 9 | 설치 종료 코드 그 밖 | `실패: winget 종료 코드 0x...`, 셋업 안 불림, 1 |
| 10 | `Error = '승격 거부됨'` | 없던 Id 가 `실패: 승격 거부됨`, 1 |
| 11 | `ANYTHING_REPO` 가 있고 그 폴더에 `pc-setup\setup.ps1` 있음 | `Invoke-Git` 안 불림, clone 그대로, 셋업이 그 폴더로 불림 |
| 12 | `ANYTHING_REPO` 가 있지만 폴더 없음 | `$HOME\anything` 로 clone |
| 13 | `$HOME\anything` 이 이미 있고 셋업 있음 | clone 그대로, `Invoke-Git` 안 불림 |
| 14 | `$HOME\anything` 이 이미 있고 셋업 없음 | clone 실패, 1 |
| 15 | `-Branch feat -Source C:\x.bundle` | `Invoke-Git clone -b feat C:\x.bundle <폴더>` |
| 16 | `-Branch` 빈 값 | `-b` 없이 clone |
| 17 | git clone 종료 코드 128 | clone 실패, 1 |
| 18 | `-Skip a,b -SetupResultPath C:\o\s.json` | `Start-SetupScript` 가 그 값으로 불림 |
| 19 | 셋업 종료 코드 1 | `Invoke-Bootstrap` 이 1 |
| 20 | `-ResultPath` 있음 | JSON 에 Results(Stage `부트스트랩`)·`ElevationRequests`·`DurationSeconds`·`Check=false`. 4·5 단계에서 멈춰도 쓴다 |

`Invoke-Bootstrap` 은 `$HOME` 을 직접 읽지 않고 `Get-DefaultRepoPath` 를 부른다. 테스트는 이 함수를 Mock 해 `TestDrive:` 아래 폴더를 돌려준다.

5.1 호환 테스트:

- `powershell.exe -NoProfile -Command` 로 `[System.Management.Automation.Language.Parser]::ParseFile('<bootstrap.ps1>', [ref]$null, [ref]$errors)` 를 돌려 오류가 0개다.
- 파일이 `EF BB BF`(UTF-8 BOM)로 시작하지 않고, 모든 바이트가 0x7F 이하다.
- 한국어 출력 문자열(결과 JSON 의 오류 문구 등)이 `[char]` 로 만든 뒤에도 spec 의 문구와 같다.
- 파일에 pwsh 7 전용 연산자(`??`, `?.`, 삼항 `? :`)가 없다는 것은 5.1 파서 검사가 잡는다.

### 에러 처리

- 각 단계의 예외는 그 단계의 `실패: <예외 메시지>` 로 바꾸고 1 을 돌려준다. 스택 추적을 출력하지 않는다.
- 결과 JSON 을 쓰지 못하면 경고를 출력하고 종료 코드는 바꾸지 않는다.

## 기존 코드 참조

- `pc-setup/setup.ps1` — 셋업 인자(`-Skip`·`-ResultPath`)와 `-Skip` 을 쉼표로 나누는 규칙.
- `pc-setup/lib/Elevation.psm1` — 셋업의 승격 단계. 같은 생각(승격 자식 하나, 결과는 임시 JSON, 거절은 `승격 거부됨`)을 5.1 과 `iex` 실행에 맞게 따른다. 이 모듈을 불러 쓰지는 않는다(부트스트랩 시점에는 저장소가 없다).
- `pc-setup/lib/Report.psm1` — 결과 글 모양(`할 일: …`, `실패: …`)과 `mm:ss` 시간 형식을 맞춘다.

## 인수 조건

- [ ] 엣지 케이스 표 1~20 과 5.1 호환 테스트가 각각 테스트로 있다.
- [ ] 테스트 중 실제 winget·git·UAC·`Add-AppxPackage` 가 불리지 않는다.
- [ ] `bootstrap.ps1` 에 `Repair-WinGetPackageManager`·`Install-Module`·`Set-ExecutionPolicy` 가 없다(테스트로 단언).
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 `bootstrap.ps1` 을 실제로 실행하는 것.
- PSGallery 를 쓰는 것, 실행 정책을 바꾸는 것, 스스로 재부팅하는 것.
- 관리자 권한으로 clone 하는 것(파일 소유자가 꼬인다).
- 이미 있는 저장소 폴더를 지우거나 pull 하는 것.
- 테스트를 건너뛰게 만드는 것(`-Skip`, 조건부 `return`), 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
