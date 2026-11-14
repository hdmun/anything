> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/85
> updatedAt: 2026-11-11T11:47:06Z

# 셋업 흐름과 승격 단계를 만든다 (-Check·-Skip·관리자 창 멈춤·ANYTHING_REPO)

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 전체 설계는 부모 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다(특히 「단계 계약」·「셋업 흐름」). 앞 태스크들이 `pc-setup/lib/Declaration.psm1`(선언 읽기·검사), `pc-setup/lib/Report.psm1`(결과·요약·종료 코드), `pc-setup/lib/ItemScript.psm1`(항목 스크립트 실행)을 만들었다.

이 태스크는 그것들을 묶는 셋업 흐름 `Invoke-Setup` 과 **승격 단계**를 만든다. 정한 것:

- 셋업은 관리자 창이면 멈춘다(`-Check` 는 예외). 관리자로 돌리면 `ElevationProhibited` 앱이 `0x8A150056` 으로 실패하고 scoop 이 실행을 거부하기 때문이다([부트스트랩 진입점과 관리자 권한 처리 정하기](https://github.com/hdmun/anything/issues/42) 「셋업」).
- 관리자 권한이 필요한 항목은 맨 앞 승격 단계에서 모아 처리한다. 실행 1회에 UAC 를 한 번만 묻는다. 셋업이 자기 자신을 `-Phase Elevated` 로 승격해 띄우고, 자식이 결과를 JSON 파일로 돌려준다.
- `-Check` 는 UAC 를 띄우지 않는다. 에이전트 세션이 불러도 멈추지 않게 하려는 것이다.
- `-Skip <Id,...>` 로 항목을 건너뛴다(결과 `건너뜀`). 끝 요약에 **승격 요청 횟수**를 찍는다([셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「셋업·부트스트랩에 더하는 것」).
- 고치는 실행이 끝나면 사용자 환경 변수 `ANYTHING_REPO` 에 저장소 경로를 남긴다. 부트스트랩이 이 값으로 이중 clone 을 막는다(같은 티켓 「부트스트랩」 2).

아직 단계(Windows 설정 등)는 없다. 기본 단계 목록은 비어 있고, 다음 태스크가 Windows 설정 단계를 더한다. 이 태스크의 테스트는 가짜 단계로 흐름을 본다.

이 PC 에서는 셋업(고치는 실행)을 돌리지 않는다. UAC 가 뜨는 경로는 `Start-Process` 를 `Mock` 으로 바꿔 시험한다.

## 범위 밖 (건드리지 말 것)

- Windows 설정 단계와 그 선언 파일: 다음 태스크.
- 부트스트랩(`bootstrap.ps1`), Sandbox 하네스: 2번 구현 이슈.
- `pc-setup/lib/Declaration.psm1`, `Report.psm1`, `ItemScript.psm1` 의 공개 함수 시그니처. 버그를 찾으면 `ask` 로 묻는다.

## 변경 대상 파일

- `pc-setup/lib/Setup.psm1` — 신규
- `pc-setup/lib/Elevation.psm1` — 신규
- `pc-setup/setup.ps1` — 수정 (뼈대를 진입점으로)
- `pc-setup/tests/Setup.Tests.ps1` — 수정 (기존 `-Check` 테스트는 남긴다)
- `pc-setup/tests/Elevation.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/setup.ps1
#Requires -Version 7
[CmdletBinding()]
param(
    [switch]$Check,
    [string[]]$Skip = @(),
    [ValidateSet('Elevated')][string]$Phase,
    [string]$ResultPath
)
# Setup.psm1 을 불러 Invoke-Setup 을 부르고, 돌려받은 종료 코드로 exit 한다.
# -Skip 은 원소마다 ',' 로 나누고 앞뒤 공백을 뗀다(pwsh -File 로 'a,b' 가 한 문자열로 오기 때문이다).
```

```powershell
# pc-setup/lib/Setup.psm1
$script:DefaultStageProviders = @()   # 단계 함수를 부르는 스크립트 블록 목록. 다음 태스크부터 순서대로 더한다.

function Invoke-Setup {
    # → 종료 코드 [int]. 결과 줄과 요약은 Write-Host 로 출력한다.
    param(
        [Parameter(Mandatory)][string]$Root,                 # pc-setup 폴더
        [switch]$Check,
        [string[]]$Skip = @(),
        [string]$Phase = '',                                 # '' 또는 'Elevated'
        [string]$ResultPath = '',
        [scriptblock[]]$StageProviders = $script:DefaultStageProviders   # 각각 param($Root) → 항목 목록
    )
}

function Set-AnythingRepo {
    # 사용자 환경 변수 ANYTHING_REPO 를 $Path 로 쓴다. 테스트는 이 함수를 Mock 한다.
    param([Parameter(Mandatory)][string]$Path)
}

Export-ModuleMember -Function Invoke-Setup, Set-AnythingRepo
```

```powershell
# pc-setup/lib/Elevation.psm1
function Test-AdminWindow {
    # 현재 프로세스가 관리자 토큰으로 돌고 있으면 $true (UAC 로 제한된 관리자 계정의 일반 창은 $false)
}

function Invoke-ElevatedPhase {
    # setup.ps1 을 승격해 '-Phase Elevated -ResultPath <임시 JSON>' 으로 띄우고 끝날 때까지 기다린다.
    # → @{ Requested = <UAC 요청 횟수 0|1>; Results = <결과 객체 배열>; Error = <'' | '승격 거부됨' | '승격 단계 결과 없음'> }
    param(
        [Parameter(Mandatory)][string]$SetupScript,
        [string[]]$Skip = @()
    )
}

Export-ModuleMember -Function Test-AdminWindow, Invoke-ElevatedPhase
```

항목·결과 객체 모양은 부모 이슈 「단계 계약」 그대로다: 항목 `{ Stage; Id; Elevated; Invoke }`, `Invoke` 는 `param([bool]$Check)` 를 받아 `@{ Status; Detail }` 를 돌려준다. 결과 객체는 `New-SetupResult` 로 만든다.

`-ResultPath` JSON 모양(UTF-8):

```json
{ "Check": false, "ElevationRequests": 1, "DurationSeconds": 252.3,
  "Results": [ { "Stage": "Windows 설정", "Id": "LongPaths", "Status": "그대로", "Detail": "" } ] }
```

## 동작 명세

### 정상 경로

`Invoke-Setup` 은 부모 이슈 「셋업 흐름」 1~7 을 그대로 한다. 세부:

1. **관리자 창 검사**: `Test-AdminWindow` 가 `$true` 이고 `-Check` 가 아니고 `Phase` 가 `Elevated` 가 아니면 `셋업은 일반 권한 창에서 실행한다 (관리자 창이면 일부 앱 설치가 실패한다)` 를 출력하고 2 를 돌려준다.
2. **선언 검사**: `$StageProviders` 를 모두 부른다. `DeclarationException` 을 던진 단계가 있어도 나머지 단계를 계속 불러 문제를 모은다. 문제가 하나라도 있으면 `선언 오류:` 다음 줄부터 문제마다 `  <문제>` 를 출력하고 2 를 돌려준다. 이때 어떤 항목의 `Invoke` 도 부르지 않는다.
3. **`-Skip` 검사**: 모르는 Id 가 있으면 `모르는 -Skip Id: <Id>` 를 출력하고 2. (Id 비교는 대소문자를 구분하지 않는다.)
4. **`Phase Elevated`**: `Elevated` 항목만 순서대로 고치는 실행으로 처리한다(건너뛸 항목은 `건너뜀`). 결과를 `-ResultPath` 에 쓰고 0 을 돌려준다. 요약은 출력하지 않는다. 결과 줄은 출력한다(승격된 창에 보인다).
5. **승격 단계**(고치는 실행, `Phase` 빈 값): 건너뛰지 않은 `Elevated` 항목이 하나라도 있으면 `Invoke-ElevatedPhase -SetupScript <Root>\setup.ps1 -Skip $Skip` 를 한 번 부른다. 돌려받은 `Results` 를 항목 순서대로 출력한다. `Error` 가 있으면 건너뛰지 않은 모든 `Elevated` 항목을 `실패: <Error>` 로 둔다. `Results` 에 없는 `Elevated` 항목은 `실패: 승격 단계 결과 없음` 이다. 건너뛸 `Elevated` 항목은 부모가 `건너뜀` 으로 둔다.
6. **일반 단계**: 고치는 실행은 `Elevated` 가 아닌 항목을, `-Check` 는 모든 항목을 순서대로 처리한다. 항목마다 결과 줄을 바로 출력한다.
7. **끝**: `Format-SetupSummary` 를 출력한다(승격 요청 횟수 = `Invoke-ElevatedPhase` 의 `Requested` 합, 걸린 시간 = 시작부터). 고치는 실행이면 `Set-AnythingRepo (Split-Path $Root -Parent)` 를 부른다(실패가 있어도 부른다). `-ResultPath` 가 있으면 JSON 을 쓴다. `Get-SetupExitCode` 를 돌려준다.

항목 하나 처리: `-Skip` 에 있으면 `건너뜀`. 아니면 `& $item.Invoke $Check` 를 부른다. 예외면 `실패: <예외 메시지>`. 돌려받은 `Status` 가 그 모드에서 허용되지 않으면(고치는 실행의 `다름`·`확인 못 함`, `-Check` 의 `바꿈`, 그 밖의 글) `실패: 모르는 결과: <Status>`.

**`Invoke-ElevatedPhase`**

- 임시 파일 경로 `$env:TEMP\pc-setup-elevated-<GUID>.json` 을 정한다.
- `Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -Wait -ArgumentList <인자>` 로 띄운다. 인자는 `-NoProfile -File "<SetupScript>" -Phase Elevated -ResultPath "<임시 파일>"`, `$Skip` 이 있으면 `-Skip "<쉼표로 이은 Id>"` 를 붙인다.
- 사용자가 UAC 를 거절하면 `Start-Process` 가 예외를 던진다 → `@{ Requested = 1; Results = @(); Error = '승격 거부됨' }`.
- 끝난 뒤 임시 파일이 없거나 JSON 이 아니면 `Error = '승격 단계 결과 없음'`. 읽은 뒤 임시 파일을 지운다.

**`setup.ps1`**: `Import-Module (Join-Path $PSScriptRoot 'lib' 'Setup.psm1') -Force` 후 `exit (Invoke-Setup -Root $PSScriptRoot ...)`. 다른 로직을 넣지 않는다.

### 엣지 케이스

`Invoke-Setup` 의 경우를 아래로 한정한다. 각 경우를 `Setup.Tests.ps1` 에 테스트로 둔다(가짜 단계 + `Mock -ModuleName Setup` 으로 `Test-AdminWindow`·`Invoke-ElevatedPhase`·`Set-AnythingRepo`). **열거하지 않은 경우는 범위 밖이다**(예: 승격된 자식이 중간에 죽는 경우의 부분 결과, 동시에 두 셋업 실행).

| # | 상황 | 기대 |
|---|---|---|
| 1 | 관리자 창 + 고치는 실행 | 2, `Invoke` 안 불림, 멈춤 문구 |
| 2 | 관리자 창 + `-Check` | 계속 진행 |
| 3 | 두 단계가 각각 `DeclarationException` | 두 단계의 문제가 모두 출력, 2, `Invoke` 안 불림 |
| 4 | 모르는 `-Skip` Id | 2 |
| 5 | 고치는 실행, `Elevated` 항목 2 + 일반 항목 2 | `Invoke-ElevatedPhase` 1번, 일반 항목은 `$Check=$false` 로 불림, 출력 순서는 승격 결과 → 일반 결과, 요약 `승격 요청: 1회` |
| 6 | `Elevated` 항목 없음, 또는 모두 `-Skip` | `Invoke-ElevatedPhase` 안 불림, `승격 요청: 0회` |
| 7 | `Invoke-ElevatedPhase` 가 `Error='승격 거부됨'` | `Elevated` 항목 모두 `실패: 승격 거부됨`, 일반 항목은 처리됨, 종료 코드 1 |
| 8 | `Results` 에 `Elevated` 항목 하나가 빠짐 | 그 항목 `실패: 승격 단계 결과 없음` |
| 9 | `-Check` | `Invoke-ElevatedPhase` 안 불림, 모든 항목이 `$Check=$true` 로 불림, `Set-AnythingRepo` 안 불림 |
| 10 | `-Skip` 한 일반 항목 | `건너뜀`, 그 `Invoke` 안 불림 |
| 11 | 항목 `Invoke` 가 예외 | `실패: <메시지>`, 다음 항목 계속 |
| 12 | 고치는 실행에서 `Invoke` 가 `다름` 을 돌려줌 | `실패: 모르는 결과: 다름` |
| 13 | `Phase Elevated` | `Elevated` 항목만 불림, JSON 씀, 요약 없음, 0, 관리자 창이어도 멈추지 않음, `Set-AnythingRepo` 안 불림 |
| 14 | 고치는 실행 + `-ResultPath` | JSON 에 결과·`ElevationRequests`·`DurationSeconds`·`Check=false` |
| 15 | 고치는 실행, 실패 있음 | `Set-AnythingRepo` 가 저장소 루트로 불림, 종료 코드 1 |
| 16 | 단계 없음(`StageProviders` 빈 목록) + `-Check` | 0, 요약 줄 출력 |

`Invoke-ElevatedPhase`(`Mock -ModuleName Elevation Start-Process`): 결과 JSON 을 쓰는 가짜 → `Results` 와 `Requested=1`; 예외 → `승격 거부됨`; 파일을 안 씀 → `승격 단계 결과 없음`; 깨진 JSON → `승격 단계 결과 없음`; `-Skip a,b` 가 인자에 `-Skip "a,b"` 로 들어감; 끝난 뒤 임시 파일이 지워짐.

`setup.ps1`: `-Skip 'a, b'` 를 넘기면 `Invoke-Setup` 이 `@('a','b')` 를 받는다(가짜 단계로 확인하거나, 단계 없이 `모르는 -Skip Id: a` 가 나오는 것으로 확인한다).

### 에러 처리

- 결과 JSON 을 쓰지 못하면(경로 오류) 예외를 그대로 둔다. 셋업 종료 코드는 PowerShell 기본 오류 처리에 맡긴다.

## 기존 코드 참조

- `pc-setup/setup.ps1` — 지금의 뼈대(`-Check` 만 받아 0). 이 태스크가 진입점으로 바꾼다.
- `pc-setup/tests/Setup.Tests.ps1` — 기존 테스트 「-Check 는 종료 코드 0 으로 끝난다」를 남긴다. 이 PC 의 실제 `-Check` 를 한 번 돌리는 통합 확인이다.
- `pc-setup/lib/Report.psm1` — `New-SetupResult`·`Format-ResultLine`·`Format-SetupSummary`·`Get-SetupExitCode`.
- `pc-setup/lib/Declaration.psm1` — `DeclarationException` 의 `Problems`.

## 인수 조건

- [ ] `Invoke-Setup` 경우 표 1~16, `Invoke-ElevatedPhase` 경우들, `setup.ps1` 의 `-Skip` 나누기가 각각 테스트로 있다.
- [ ] 테스트 중 실제 UAC 창이 뜨지 않고, 실제 사용자 환경 변수 `ANYTHING_REPO` 가 바뀌지 않는다(`Start-Process`·`Set-AnythingRepo` 를 Mock).
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 0 으로 끝나고 요약 줄을 출력한다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 `setup.ps1` 을 `-Check` 없이 돌리는 것, 실제 UAC 를 띄우는 테스트.
- 셋업을 통째로 관리자로 돌리는 설계(승격은 `-Phase Elevated` 자식 하나뿐이다).
- 기존 `-Check` 테스트를 지우는 것, 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
