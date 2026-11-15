> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/94
> updatedAt: 2026-11-15T08:58:25Z

# 앱 선언 스키마와 앱 항목 만들기, 공식 배포 처리, PATH 다시 읽기를 만든다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)이 셋업 뼈대를 만들었다: 선언 읽기(`lib/Declaration.psm1` 의 `Read-Declaration`·`DeclarationException`), 결과·요약(`lib/Report.psm1`), 항목 스크립트 실행(`lib/ItemScript.psm1` 의 `Invoke-ItemScript`), 셋업 흐름·승격 단계(`lib/Setup.psm1`·`lib/Elevation.psm1`), 첫 단계인 Windows 설정(`lib/WindowsSettings.psm1`). 설계 전체는 그 이슈의 「공통 설계」 절에 있다.

이 태스크는 앱 단계의 골격을 만든다. 부모 이슈는 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)이다.

- 앱 선언 `pc-setup/apps.psd1` 은 한 줄 한 앱이다. 앱마다 **원천**이 하나다: `Origin` 을 생략하면 winget, 그 밖에는 `scoop`·`nvm`·`pnpm`·`go`·`official`(공식 배포)([앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44) 「항목 키」, [런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62), [런타임 전역 패키지 선언 정하기](https://github.com/hdmun/anything/issues/67)).
- 승격 여부: winget 은 `Scope = 'machine'` 이거나 `Elevated = $true` 면 **승격 단계**에서 처리한다(`Elevated` 는 py 런처 때문에 Python 에 쓴다). msstore 앱(`WingetSource = 'msstore'`)은 일반 권한이고 `Scope` 를 쓰지 않는다. #44 의 「msstore 앱은 일반 권한」을 이렇게 읽었다. scoop·nvm·pnpm·go 는 항상 일반 권한이다. 공식 배포는 `Elevated` 키로 정한다.
- 공식 배포 앱은 `pc-setup/apps/<Id>.ps1` 항목 스크립트로 처리한다(1번 이슈 「항목 스크립트 규칙」). 실제 스크립트 9개와 선언 줄은 4번 구현 이슈 [pc-setup 앱: 공식 배포 9개](https://github.com/hdmun/anything/issues/99)가 더한다. 이 태스크는 그 일반 처리만 만든다.
- scoop nvm·Flutter·Go 처럼 PATH 를 바꾸는 설치 뒤에는, 같은 셋업 실행 안에서 다음 항목이 그 명령을 쓰도록 PATH 를 레지스트리에서 다시 읽어야 한다(#62 「구현 메모」). 그래서 `pc-setup/lib/EnvPath.psm1` 을 만든다. 4번 이슈의 `apps/claude-code.ps1`(`~/.local/bin` 을 사용자 PATH 맨 앞에)과 Flutter(`bin`)도 이 모듈을 쓴다.

원천별 실제 확인·설치(winget·scoop·nvm·pnpm·go)는 이 이슈의 다음 태스크들이 채운다. 이 태스크는 원천별 처리 함수의 **자리**만 만든다: 세 모듈 파일에 함수를 두고, 몸통은 `throw '아직 구현되지 않은 원천: <원천>'` 한 줄이다. 셋업 흐름은 예외를 `실패: <메시지>` 로 바꾼다. 앱 단계는 마지막 태스크에서 셋업에 등록하므로, 그 전에는 이 자리가 실제로 불리지 않는다.

Pester 6.2.0 이 이 PC 에 설치돼 있다. 이 PC 에서는 셋업(고치는 실행)을 돌리지 않는다.

## 범위 밖 (건드리지 말 것)

- 원천별 실제 처리: winget(둘째 태스크), scoop(셋째), nvm·pnpm·go(넷째).
- 실제 `pc-setup/apps.psd1`, `Setup.psm1` 의 단계 등록: 마지막 태스크.
- 공식 배포 스크립트(`pc-setup/apps/*.ps1`): 4번 구현 이슈.
- 1번 이슈가 만든 모듈의 공개 함수 시그니처. 버그를 찾으면 `ask` 로 묻는다.

## 변경 대상 파일

- `pc-setup/lib/Apps.psm1` — 신규
- `pc-setup/lib/AppWinget.psm1` — 신규 (자리만)
- `pc-setup/lib/AppScoop.psm1` — 신규 (자리만)
- `pc-setup/lib/AppRuntime.psm1` — 신규 (자리만)
- `pc-setup/lib/EnvPath.psm1` — 신규
- `pc-setup/tests/Apps.Tests.ps1` — 신규
- `pc-setup/tests/EnvPath.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/Apps.psm1
function Get-AppItems {
    # <Root>\apps.psd1 을 읽고 검사해 앱 항목 목록을 돌려준다(Stage = '앱'). 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)
}
Export-ModuleMember -Function Get-AppItems
```

```powershell
# 원천별 처리 함수. 모두 같은 모양이다: $Entry 는 선언 항목(Read-Declaration 이 돌려준 객체), 결과는 @{ Status; Detail }.
# pc-setup/lib/AppWinget.psm1
function Invoke-WingetApp  { param([Parameter(Mandatory)]$Entry, [bool]$Check) }
# pc-setup/lib/AppScoop.psm1
function Invoke-ScoopApp   { param([Parameter(Mandatory)]$Entry, [bool]$Check) }
# pc-setup/lib/AppRuntime.psm1
function Invoke-NvmApp     { param([Parameter(Mandatory)]$Entry, [bool]$Check) }
function Invoke-PnpmApp    { param([Parameter(Mandatory)]$Entry, [bool]$Check) }
function Invoke-GoApp      { param([Parameter(Mandatory)]$Entry, [bool]$Check) }
# 이 태스크에서는 몸통이 throw '아직 구현되지 않은 원천: <winget|scoop|nvm|pnpm|go>' 다. 각 모듈은 자기 함수를 Export-ModuleMember 한다.
```

```powershell
# pc-setup/lib/EnvPath.psm1
function Update-SessionPath {
    # 시스템 PATH(HKLM) 다음에 사용자 PATH(HKCU)를 이어 현재 프로세스 $env:Path 로 둔다. 환경 변수(%...%)는 펼친다.
}
function Add-UserPath {
    # 사용자 PATH 에 $Path 가 없을 때만 넣는다(-Prepend 면 맨 앞, 아니면 맨 뒤). 바꿨으면 $true, 이미 있으면 $false.
    # 넣은 뒤 Update-SessionPath 를 부른다.
    param([Parameter(Mandatory)][string]$Path, [switch]$Prepend)
}
function Get-UserPathEntries   { }                                   # 사용자 PATH 를 ';' 로 나눈 목록. 테스트는 Mock 한다.
function Set-UserPathEntries   { param([string[]]$Entries) }          # 사용자 PATH 를 쓴다. 테스트는 Mock 한다.
Export-ModuleMember -Function Update-SessionPath, Add-UserPath, Get-UserPathEntries, Set-UserPathEntries
```

## 동작 명세

### 정상 경로

**스키마** (`Read-Declaration` 에 넘긴다)

- `Key = 'Id'`, `Required = @('Id')`, `Allowed = @('Id','Origin','Scope','WingetSource','Bucket','Elevated','Line')`.
- `Enums = @{ Origin = @('winget','scoop','nvm','pnpm','go','official'); Scope = @('machine','user'); WingetSource = @('msstore'); Bucket = @('main','extras') }`. `Origin` 이 없으면 `winget` 이다.
- `Validate`(항목 하나, 문제 문구는 그대로 쓴다). 원천마다 쓸 수 있는 키:

| 원천 | 필수 | 선택 | 그 밖의 키 |
|---|---|---|---|
| winget (msstore 아님) | `Scope` | `Elevated` | 문제 |
| winget msstore (`WingetSource = 'msstore'`) | | | `Scope`·`Elevated`·`Bucket`·`Line` 은 문제 |
| scoop | `Bucket` | | 문제 |
| nvm | `Line` | | 문제 |
| pnpm, go | | | 문제 |
| official | | `Elevated` | 문제 |

  - 빠진 필수 키: `<원천> 항목에는 '<키>' 가 있어야 한다`
  - 쓸 수 없는 키: `<원천> 항목에는 '<키>' 를 쓰지 않는다` (msstore 는 원천 자리에 `winget msstore`)
  - `Elevated` 가 `$true`/`$false` 가 아님: `'Elevated' 는 $true 또는 $false 다`
  - `Line` 이 문자열이 아니거나 빈 값: `'Line' 은 버전 줄 문자열이다 (예: '26')`
- `Get-AppItems` 는 `Read-Declaration` 뒤에 `official` 항목마다 `<Root>\apps\<Id>.ps1` 이 있는지 본다. 없으면 `apps.psd1:<줄>: 스크립트가 없다: apps/<Id>.ps1` 문제를 더한다(다른 문제와 함께 모아 `DeclarationException`).

**항목** (선언 순서대로)

- `Stage = '앱'`, `Id = <Id>`.
- `Elevated`: winget 은 `Scope -eq 'machine' -or Elevated -eq $true`, msstore·scoop·nvm·pnpm·go 는 `$false`, official 은 `[bool]$Elevated`.
- `Invoke`: 원천에 따라 `Invoke-WingetApp`(msstore 포함)·`Invoke-ScoopApp`·`Invoke-NvmApp`·`Invoke-PnpmApp`·`Invoke-GoApp` 에 `-Entry <항목> -Check $Check` 로 넘긴다. official 은 `Invoke-ItemScript -Path <Root>\apps\<Id>.ps1 -Check:$Check`.

**`EnvPath.psm1`**

- `Update-SessionPath`: `[Environment]::GetEnvironmentVariable('Path','Machine')` 와 `'User'` 를 `;` 로 잇는다. 빈 조각은 뺀다. `[Environment]::ExpandEnvironmentVariables` 로 펼친다.
- `Add-UserPath`: 비교는 대소문자를 구분하지 않고 끝의 `\` 를 무시한다. 이미 있으면(위치와 상관없이) `$false` 를 돌려주고 쓰지 않는다. 없으면 `-Prepend` 에 따라 맨 앞·맨 뒤에 넣어 `Set-UserPathEntries` 로 쓰고 `Update-SessionPath` 를 부른 뒤 `$true`.
- `Get-UserPathEntries`·`Set-UserPathEntries` 는 사용자 PATH 를 레지스트리 `HKCU:\Environment` 의 `Path` 로 읽고 쓴다. 값 종류(`REG_EXPAND_SZ`)를 유지한다. 쓴 뒤 환경 변경 알림(`WM_SETTINGCHANGE`, lParam `Environment`)을 보낸다. `[Environment]::SetEnvironmentVariable(..., 'User')` 를 써도 된다(알림을 함께 보낸다). 단 `%USERPROFILE%` 같은 펼치지 않은 값이 펼쳐진 값으로 바뀌지 않게 한다.

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다(`TestDrive:` 에 가짜 `Root` 와 `apps.psd1`, 원천별 함수는 `Mock -ModuleName Apps`). **열거하지 않은 경우는 범위 밖이다**(예: 같은 앱이 다른 원천으로 두 줄, `Line` 의 형식 검사).

| # | 선언 | 기대 |
|---|---|---|
| 1 | winget `Scope='machine'` | `Elevated $true`, `Invoke-WingetApp` 으로 넘김 |
| 2 | winget `Scope='user'` | `Elevated $false` |
| 3 | winget `Scope='user'; Elevated=$true` | `Elevated $true` |
| 4 | winget `Scope` 없음 | 「winget 항목에는 'Scope' 가 있어야 한다」 |
| 5 | msstore, `Scope` 없음 | `Elevated $false`, `Invoke-WingetApp` 으로 넘김 |
| 6 | msstore + `Scope='user'` | 「winget msstore 항목에는 'Scope' 를 쓰지 않는다」 |
| 7 | scoop `Bucket='extras'` | `Elevated $false`, `Invoke-ScoopApp` |
| 8 | scoop `Bucket` 없음 / `Bucket='versions'` | 필수 키 문제 / 허용 값 문제 |
| 9 | nvm `Line='26'` | `Invoke-NvmApp` |
| 10 | nvm `Line` 없음 | 필수 키 문제 |
| 11 | pnpm / go | 각각 `Invoke-PnpmApp` / `Invoke-GoApp`, `Elevated $false` |
| 12 | pnpm + `Scope` | 「pnpm 항목에는 'Scope' 를 쓰지 않는다」 |
| 13 | official + `apps/<Id>.ps1` 있음, `Elevated=$true` | `Elevated $true`, `Invoke` 가 스크립트 결과를 돌려줌 |
| 14 | official + 스크립트 없음 | 「스크립트가 없다: apps/<Id>.ps1」 |
| 15 | `Origin='brew'` | 허용 값 문제 |
| 16 | `Invoke` 에 `$Check=$true` | 원천 함수가 `-Check $true` 를 받음 |
| 17 | 원천 함수 자리(Mock 없이) | `아직 구현되지 않은 원천: <원천>` 예외 |

`EnvPath`(`Get-UserPathEntries`·`Set-UserPathEntries` 를 Mock): 없는 경로 뒤에 넣기 / `-Prepend` 로 맨 앞 / 이미 있음(대소문자·끝 `\` 다름) → `$false`, 쓰기 안 불림 / 넣은 뒤 `Update-SessionPath` 가 불림. `Update-SessionPath` 는 `[Environment]::GetEnvironmentVariable` 을 감싼 함수를 Mock 하거나, 테스트 전후로 `$env:Path` 를 저장·복원하고 결과에 시스템·사용자 조각이 순서대로 들어가는지 본다.

### 에러 처리

- 원천 함수가 던진 예외는 잡지 않는다. 셋업 흐름이 `실패: <메시지>` 로 바꾼다.
- 테스트에서 실제 사용자 PATH 를 쓰지 않는다.

## 기존 코드 참조

- `pc-setup/lib/WindowsSettings.psm1` — 같은 모양의 단계 모듈. `Get-WindowsSettingItems` 의 스키마·`Validate`·스크립트 존재 검사·항목 만들기를 따른다.
- `pc-setup/lib/Declaration.psm1` — `Read-Declaration`, 스키마 해시테이블 모양, `DeclarationException`.
- `pc-setup/lib/ItemScript.psm1` — `Invoke-ItemScript`.
- `pc-setup/tests/WindowsSettings.Tests.ps1` — `TestDrive:` 가짜 `Root` 로 단계 모듈을 시험하는 방식.

## 인수 조건

- [ ] 엣지 케이스 표 1~17 과 `EnvPath` 경우가 각각 테스트로 있다.
- [ ] 테스트가 실제 사용자 PATH·레지스트리를 쓰지 않는다.
- [ ] `Apps.psm1` 을 불러와도 셋업의 단계 목록은 그대로다(`Setup.psm1` 을 고치지 않는다).
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 원천별 실제 처리(winget·scoop 등 외부 명령 호출)를 이 태스크에서 만드는 것.
- `Origin = 'winget'` 을 선언에 쓰라고 강제하는 것(생략이 기본이다).
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
