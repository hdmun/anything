> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/106
> updatedAt: 2026-11-11T11:47:41Z

# 설정 파일 처리(Link·GitInclude)와 선언 읽기를 만든다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 1~4번 구현 이슈가 셋업 뼈대(선언 읽기 `lib/Declaration.psm1`, 결과·요약 `lib/Report.psm1`, 셋업 흐름·승격 단계 `lib/Setup.psm1`·`lib/Elevation.psm1`, 항목 스크립트 실행 `lib/ItemScript.psm1`)와 Windows 설정·앱 단계를 만들었다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다. 이 이슈의 부모는 [pc-setup 설정 파일과 저장소 도구](https://github.com/hdmun/anything/issues/105)이다.

이 태스크는 **설정 파일** 단계의 처리 로직을 만든다([설정 파일 관리 방식 정하기: symlink·복사](https://github.com/hdmun/anything/issues/45)). 설정 파일은 앱이 읽는 사용자 설정 가운데 선언이 다루는 것이고, 정본은 저장소에 있다. PC 의 원래 자리에서는 둘 중 한 방식으로 연결한다.

- `Link`: 원래 자리에 저장소 파일을 가리키는 symlink 를 건다(WT `settings.json`, `~/.nanorc`). hardlink 는 쓰지 않는다([설정 파일 symlink 연결 시 깨지는 앱과 Developer Mode 조건](https://github.com/hdmun/anything/issues/38)). Developer Mode 가 켜져 있으면 pwsh 7 이 일반 권한으로 symlink 를 만든다. Developer Mode 는 Windows 설정 단계(승격 단계)가 먼저 켠다.
- `GitInclude`: 원래 자리(`~/.gitconfig`)는 PC 전용 **로컬 파일**로 두고, 맨 위의 `[include]` 줄로 저장소 파일을 불러온다. 그 PC 에만 맞는 값(`gh auth setup-git` 이 쓰는 줄 등)은 로컬 파일에 남는다.
- 처음 결정에 있던 `DotSource`(PowerShell 프로필)는 프로필 항목이 셋업 밖으로 나가서([에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64)) 만들지 않는다.
- 선언에 없는 설정 파일은 보지도, 알리지도, 지우지도 않는다([선언에 없는 앱(드리프트) 처리 정하기](https://github.com/hdmun/anything/issues/65)).

실제 선언 파일(`config-files.psd1`)·저장소 설정 파일(`config/*`)·단계 등록은 다음 태스크다. 이 태스크의 테스트는 `TestDrive:` 에 만든 가짜 `Root` 와 가짜 대상 파일만 쓴다. 이 PC 의 실제 `~/.gitconfig`·`~/.nanorc`·WT 설정을 건드리지 않는다. 이 PC 에는 Developer Mode 가 켜져 있어 `TestDrive:` 안에서 symlink 를 만들 수 있다. Pester 6.2.0 이 설치돼 있다.

## 범위 밖 (건드리지 말 것)

- `pc-setup/config-files.psd1`, `pc-setup/config/*`, `pc-setup/lib/Setup.psm1` 의 단계 목록: 다음 태스크.
- 저장소 도구 단계: 뒤 태스크.
- `DotSource` 방식, 문서 폴더 경로 펼치기.
- 로컬 파일 안의 중복 섹션 찾기·지우기(검증 PC 체크리스트가 손으로 한다, 6번 이슈).
- `lib/Declaration.psm1`·`lib/Report.psm1`·`lib/ItemScript.psm1`·`lib/Setup.psm1` 의 공개 함수 시그니처. 버그를 찾으면 `ask` 로 묻는다.

## 변경 대상 파일

- `pc-setup/lib/ConfigFiles.psm1` — 신규
- `pc-setup/tests/ConfigFiles.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/ConfigFiles.psm1

function Get-ConfigFileItems {
    # <Root>\config-files.psd1 을 읽고 검사해 항목 목록을 돌려준다.
    # 항목: Stage = '설정 파일', Id = 선언의 Path 글 그대로, Elevated = $false.
    # 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)
}

function Invoke-LinkFile {
    # Destination 에 Source 를 가리키는 symlink 가 있게 한다 → @{ Status; Detail }
    param(
        [Parameter(Mandatory)][string]$Destination,   # 펼친 원래 자리 전체 경로
        [Parameter(Mandatory)][string]$Source,        # 저장소 파일 전체 경로
        [bool]$Check
    )
}

function Invoke-GitIncludeFile {
    # Destination(로컬 gitconfig) 맨 위 [include] 에 Source 를 불러오는 줄이 있게 한다 → @{ Status; Detail }
    param(
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string]$Source,
        [string]$SourceKey = 'pc-setup/config/gitconfig',   # 경로가 다른 기존 줄을 알아보는 끝부분
        [bool]$Check
    )
}

Export-ModuleMember -Function Get-ConfigFileItems, Invoke-LinkFile, Invoke-GitIncludeFile
```

모듈 안의 작은 함수(테스트가 `Mock -ModuleName ConfigFiles` 로 바꾼다):

```powershell
function Get-BackupStamp { (Get-Date).ToString('yyyyMMdd-HHmmss') }
function New-SymbolicLink { param([string]$Path, [string]$Target) New-Item -ItemType SymbolicLink -Path $Path -Target $Target -Force | Out-Null }
function Test-DeveloperMode {
    # HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock 의 AllowDevelopmentWithoutDevLicense 가 1 이면 $true
}
```

## 동작 명세

### 선언 스키마 (`config-files.psd1`)

```powershell
@{ Path = '~/.gitconfig'; Method = 'GitInclude'; Source = 'config/gitconfig' }
```

- `Key = 'Path'`, `Required = @('Path','Method','Source')`, `Allowed = @('Path','Method','Source')`, `Enums = @{ Method = @('Link','GitInclude') }`.
- `Source` 는 `pc-setup` 폴더(`$Root`) 기준 상대 경로다. `Get-ConfigFileItems` 는 `Read-Declaration` 뒤에 항목마다 `Join-Path $Root $Source` 파일이 있는지 본다. 없으면 `config-files.psd1:<줄>: 저장소 파일이 없다: <Source>` 문제를 더해 `DeclarationException` 을 던진다(다른 문제와 함께 모은다).
- `Source` 가 절대 경로이거나 `..` 을 포함하면 `config-files.psd1:<줄>: Source 는 pc-setup 폴더 안의 상대 경로다` 문제(`Validate`).

### 항목

- `Invoke = { param($Check) ... }`: 먼저 `Expand-SetupPath $Path` 로 원래 자리를 펼친다. 환경 변수가 없어 예외가 나면 `실패: <예외 메시지>` 를 돌려준다(선언 오류가 아니다. PC 상태다). 그다음 `Method` 에 따라 `Invoke-LinkFile` 또는 `Invoke-GitIncludeFile` 을 `-Source (Join-Path $Root $Source 의 전체 경로)` 로 부른다.
- 저장소 경로는 `$Root`(셋업이 `$PSScriptRoot` 로 계산한 `pc-setup` 폴더)에서만 얻는다. 저장소 위치를 하드코딩하지 않는다.

### `Invoke-LinkFile`

| # | 원래 자리 상태 | `-Check` | 고치는 실행 |
|---|---|---|---|
| 1 | 비어 있음(부모 폴더 있음) | `다름 (없음)` | 링크를 만들고 `바꿈` |
| 2 | 비어 있음, 부모 폴더도 없음 | `다름 (없음)` | 부모 폴더를 만들고(`New-Item -ItemType Directory -Force`) 링크, `바꿈` |
| 3 | Source 를 가리키는 symlink | `그대로` | `그대로` |
| 4 | 다른 곳을 가리키는 symlink(저장소를 옮긴 경우 등) | `다름 (다른 곳을 가리키는 링크)` | 백업 없이 링크를 지우고 다시 걸어 `바꿈` |
| 5 | 일반 파일, 내용이 Source 와 다름 | `다름 (일반 파일)` | `<자리>.bak-<Get-BackupStamp>` 로 옮긴 뒤 링크, `바꿈 (백업: <백업 전체 경로>)` |
| 6 | 일반 파일, 내용이 Source 와 바이트까지 같음 | `다름 (일반 파일)` | 백업 없이 지운 뒤 링크, `바꿈` |
| 7 | 폴더가 있음 | `실패: 링크 자리에 폴더가 있다` | `실패: 링크 자리에 폴더가 있다` |
| 8 | 링크 만들기에서 예외, `Test-DeveloperMode` 가 `$false` | — | `실패: Developer Mode 꺼짐` |
| 9 | 링크 만들기에서 예외, Developer Mode 켜짐 | — | `실패: 링크를 만들지 못했다: <예외 메시지>` |

- 링크 판정: `(Get-Item -Force <자리>).LinkType -eq 'SymbolicLink'` 이고, 대상(`.Target`, 상대 경로면 자리의 폴더 기준으로 풀어서)의 전체 경로가 Source 의 전체 경로와 같으면(대소문자 무시) 3번이다.
- 대상이 없는(끊어진) symlink 도 4번이다.
- 링크 대상은 Source 의 **전체 경로**로 건다.
- 8·9번에서 5번의 백업은 이미 끝났을 수 있다. 백업 파일은 그대로 둔다(되돌리지 않는다).
- `-Check` 는 아무것도 만들거나 옮기지 않는다.

### `Invoke-GitIncludeFile`

불러오는 줄은 `[include]` 섹션 안의 `path = <값>` 줄이다. 원하는 값은 Source 전체 경로의 `\` 를 `/` 로 바꾼 것이다(예: `C:/Users/me/anything/pc-setup/config/gitconfig`). 쓸 때는 큰따옴표로 감싼다: `path = "C:/Users/me/anything/pc-setup/config/gitconfig"`. 읽을 때는 앞뒤 공백과 큰따옴표를 떼고 `\` 를 `/` 로 바꿔 대소문자 무시로 비교한다.

| # | 로컬 파일 상태 | `-Check` | 고치는 실행 |
|---|---|---|---|
| 1 | 파일 없음 | `다름 (파일 없음)` | `[include]` 와 `path = "<값>"` 두 줄만 든 파일을 만들고 `바꿈` |
| 2 | 불러오는 줄 없음(다른 섹션만 있음) | `다름 (불러오는 줄 없음)` | 맨 위에 `[include]`·`\tpath = "<값>"` 두 줄을 넣고 `바꿈`. 기존 줄은 그대로 아래에 둔다 |
| 3 | `[include]` 의 `path` 값이 원하는 값과 같음(위치는 따지지 않음) | `그대로` | `그대로` |
| 4 | `[include]` 의 `path` 값이 `SourceKey` 로 끝나지만 앞 경로가 다름(저장소를 옮긴 경우) | `다름 (경로 다름)` | 그 줄의 값만 원하는 값으로 바꾸고 `바꿈`. 다른 줄은 그대로 |
| 5 | 2·4 에서 다른 섹션·주석·빈 줄 | — | 글자 하나 바뀌지 않고 남는다 |
| 6 | `[include]` 섹션이 있지만 `path` 가 다른 파일(`SourceKey` 로 끝나지 않음) | `다름 (불러오는 줄 없음)` | 2 와 같이 맨 위에 새로 넣는다. 기존 `[include]` 는 그대로 |

- 섹션 이름은 대소문자를 무시한다(`[Include]`). 키 `path` 도 대소문자를 무시한다.
- 파일을 다시 쓸 때 기존 줄바꿈(CRLF 또는 LF, 첫 줄바꿈으로 판정)을 유지한다. 새 파일은 LF 다. 인코딩은 BOM 없는 UTF-8 이다.
- 부모 폴더가 없을 일은 없다(`~` 가 원래 자리다). 이 경우는 범위 밖이다.

### 엣지 케이스

경우를 위 두 표와 아래로 한정한다. 각 행을 `ConfigFiles.Tests.ps1` 에 테스트 하나 이상으로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: hardlink·junction 이 있는 자리, 같은 초에 백업이 두 번 생기는 경우, `[include]` 가 여러 개이고 둘 다 `SourceKey` 로 끝나는 경우, gitconfig 의 `\` 이어 쓰기 줄). 범위 밖 경우의 결과는 테스트하지 않는다.

- `Get-ConfigFileItems`: 정상 3줄(`Link` 2·`GitInclude` 1) → 항목 3개, `Id` 는 `Path` 글, `Elevated` 모두 `$false` / `Source` 파일 없음 → 「저장소 파일이 없다」 / `Method = 'DotSource'` → 허용 값 문제 / `Source = '../x'` → 「pc-setup 폴더 안의 상대 경로」 / 같은 `Path` 두 줄 → 중복 문제.
- 항목 `Invoke`: 없는 환경 변수가 든 `Path` → `실패: 환경 변수 '<이름>' 이 없다`.
- `Invoke-LinkFile` 5번: `Mock Get-BackupStamp { '20261111-101500' }` 로 백업 이름을 고정해 `바꿈 (백업: <자리>.bak-20261111-101500)` 과 백업 파일 내용(원래 내용)을 본다.
- `Invoke-LinkFile` 8·9번: `Mock New-SymbolicLink { throw 'x' }` 와 `Mock Test-DeveloperMode { $false }`/`{ $true }`.
- 두 번째 고치는 실행: 1·2·4·5 다음에 다시 부르면 `그대로`(멱등).
- `Invoke-GitIncludeFile` 1~6, CRLF 파일 유지, 두 번째 고치는 실행이 `그대로`.

### 에러 처리

- 파일 읽기·쓰기 예외는 잡지 않아도 된다. 셋업 흐름이 `실패: <메시지>` 로 바꾼다. 위 표의 `실패` 는 이 함수가 직접 돌려준다.

## 기존 코드 참조

- `pc-setup/lib/WindowsSettings.psm1` — 단계 모듈 모양: `Get-<단계>Items` 가 스키마로 `Read-Declaration` 을 부르고, 추가 검사(파일 존재) 문제를 모아 `DeclarationException` 을 던지는 방식.
- `pc-setup/lib/Declaration.psm1` — `Read-Declaration`·`DeclarationException`·`Expand-SetupPath`(`~`·`$env:<이름>` 만 펼친다).
- `pc-setup/tests/WindowsSettings.Tests.ps1` — `TestDrive:` 에 가짜 `Root` 를 만드는 테스트 모양.

## 인수 조건

- [ ] `Invoke-LinkFile` 표 1~9, `Invoke-GitIncludeFile` 표 1~6, 엣지 케이스 목록이 각각 테스트로 있다.
- [ ] 테스트가 `TestDrive:` 밖의 파일(이 PC 의 `~/.gitconfig`·`~/.nanorc`·WT 설정)을 만들거나 바꾸지 않는다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- hardlink·복사로 연결하는 것, `DotSource` 를 만드는 것.
- 로컬 파일의 다른 줄을 고치거나 지우는 것, 불러오는 줄의 위치를 옮기는 것.
- 견본·템플릿 파일을 만드는 것(개인값은 로컬 파일에 사람이 적는다).
- 이 PC 에서 셋업을 `-Check` 없이 돌리는 것.
- 테스트를 건너뛰게 만드는 것(`-Skip`, 조건부 `return`), 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
