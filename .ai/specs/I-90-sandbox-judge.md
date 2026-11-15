> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/90
> updatedAt: 2026-11-11T11:47:14Z

# Sandbox 실행 결과를 예상 결과로 판정하는 모듈과 예상 결과 파일을 만든다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」를 따른다. 이 이슈(부모 [pc-setup 부트스트랩과 Sandbox 하네스](https://github.com/hdmun/anything/issues/88))는 깨끗한 Windows Sandbox 에서 부트스트랩 → 셋업 → 셋업 재실행을 돌리는 하네스(검증 층 3)를 만든다. 앞 태스크가 `pc-setup/bootstrap.ps1` 을 만들었다.

이 태스크는 하네스의 **판정** 부분만 만든다. Sandbox 를 띄우는 쪽(뒤 태스크 둘)과 떼어 놓아, 판정은 Pester 로 시험할 수 있게 한다. 정한 것([셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「예상 결과」·「멱등 판정」·「완료 조건 수치」):

- **예상 결과**: Sandbox 가 실제 PC 와 달라서 같은 결과가 나올 수 없는 항목과, 그 항목에 허용하는 결과(`건너뜀`·`실패`·`할 일`)를 적은 목록. 파일은 `pc-setup/test/sandbox-expected.psd1`, 항목마다 `Id`·결과·이유. 목록에 없는 항목은 실제 PC 와 같은 결과를 내야 한다.
- 합격: 첫 실행(부트스트랩 + 부트스트랩이 부른 셋업)에 `실패` 0개, 두 번째 고치는 실행에 `바꿈`·`실패` 0개. 예상 결과에 적은 항목은 뺀다.
- 허용 결과로 적었는데 실제로 `그대로` 가 나오면 경고한다. 필요 없어진 예외가 쌓이지 않게 하려는 것이다.
- 승격 요청 횟수: 첫 실행 2회(부트스트랩 1 + 셋업 1), 재실행 1회. Sandbox 에서는 하네스가 자동으로 확인한다.
- 시간은 합격 조건이 아니다. 기록만 한다.

이 이슈 시점에는 앱 단계가 없다(Windows 설정 단계만 있다). 그래서 이 태스크의 예상 결과 파일은 빈 목록으로 시작한다. Windows 설정 가운데 Sandbox 에서 다르게 나오는 것은 머지 전에 사람이 첫 Sandbox 실행 결과를 보고 채운다(부모 「사람이 할 일」). `wsl`·Ubuntu·`hyper-v`·`windows-sandbox`(건너뜀, Sandbox 안에서 Windows 기능을 켤 수 없음)와 Docker Desktop·iCloud(허용 `실패`, Store 가 없음) 줄은 그 앱을 선언에 넣는 3·4번 구현 이슈가 더한다.

예상 결과의 `Id` 가 선언에 없을 때: 하네스는 Sandbox 를 띄우기 전에 멈춘다(뒤 태스크). 셋업은 모르는 `-Skip` Id 를 받으면 종료 코드 2 로 멈추고, 빼 버린 앱의 예외가 남아 있으면 그것을 찾기 어렵기 때문이다. 그 검사에 필요한 「선언의 모든 항목 목록」 함수를 이 태스크가 `Setup.psm1` 에 더한다.

Pester 6.2.0 이 이 PC 에 설치돼 있다.

## 범위 밖 (건드리지 말 것)

- Sandbox 를 띄우거나 Sandbox 안에서 도는 스크립트: 뒤 태스크.
- `Invoke-Setup` 의 동작, 다른 `lib/*.psm1` 공개 함수의 시그니처.
- 앱 항목의 예상 결과 줄: 3·4번 구현 이슈.

## 변경 대상 파일

- `pc-setup/test/SandboxJudge.psm1` — 신규
- `pc-setup/test/sandbox-expected.psd1` — 신규
- `pc-setup/lib/Setup.psm1` — 수정 (`Get-SetupItems` 추가·내보내기)
- `pc-setup/tests/SandboxJudge.Tests.ps1` — 신규
- `pc-setup/tests/Setup.Tests.ps1` — 수정 (`Get-SetupItems` 테스트 추가)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/Setup.psm1 (추가)
function Get-SetupItems {
    # 기본 단계 목록($script:DefaultStageProviders)의 모든 항목을 단계 순서대로 돌려준다. 아무것도 실행하지 않는다.
    # 선언 문제가 있으면 모든 단계의 문제를 모아 DeclarationException 하나로 던진다.
    param([Parameter(Mandatory)][string]$Root)
}
```

```powershell
# pc-setup/test/SandboxJudge.psm1

function Read-SandboxExpected {
    # sandbox-expected.psd1 을 Read-Declaration 으로 읽는다 → 항목(Id, Result, Reason, Line)
    param([Parameter(Mandatory)][string]$Path)
}

function Test-SandboxExpectedIds {
    # 예상 결과 Id 가운데 선언 Id 목록에 없는 것 → 문제 문자열 배열('sandbox-expected.psd1:<줄>: 선언에 없는 Id '<Id>'')
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected, [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$DeclaredIds)
}

function Get-SandboxSkipIds {
    # Result 가 '건너뜀' 인 예상 결과 Id
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected)
}

function Test-SandboxRun {
    # Sandbox 안 스크립트가 쓴 result.json(객체) + 예상 결과 → 판정
    # → [pscustomobject]@{ Passed = [bool]; Failures = [string[]]; Warnings = [string[]]; Runs = [object[]]; ExpectedHits = [int] }
    param(
        [Parameter(Mandatory)]$Run,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Expected,
        [int]$FirstRunElevations = 2,
        [int]$RerunElevations = 1
    )
}

function Format-SandboxReport {
    # 판정 → 요약 표 줄들 [string[]]
    param([Parameter(Mandatory)]$Judgment)
}

Export-ModuleMember -Function Read-SandboxExpected, Test-SandboxExpectedIds, Get-SandboxSkipIds, Test-SandboxRun, Format-SandboxReport
```

`result.json` 모양(뒤 태스크의 Sandbox 안 스크립트가 이 모양으로 쓴다):

```json
{
  "Error": "",
  "Runs": [
    { "Name": "bootstrap", "ExitCode": 0, "Result": { "Check": false, "ElevationRequests": 1, "DurationSeconds": 95.2, "Results": [ ... ] } },
    { "Name": "setup-1",   "ExitCode": 0, "Result": { ...셋업 -ResultPath JSON... } },
    { "Name": "setup-2",   "ExitCode": 0, "Result": { ... } }
  ]
}
```

`Result` 는 그 실행의 결과 JSON 을 그대로 넣은 것이고, 파일이 없었으면 `null` 이다. `Error` 는 Sandbox 안 스크립트 자체의 오류다(없으면 빈 문자열).

`sandbox-expected.psd1` (이 태스크가 만드는 내용):

```powershell
# 예상 결과: Windows Sandbox 가 실제 PC 와 달라서 같은 결과가 나올 수 없는 항목과 허용 결과.
# Result: 건너뜀(셋업에 -Skip 으로 넘김) | 실패 | 할 일. 시험 환경의 차이만 적는다.
# 예: @{ Id = 'XP8CBJ40XLBWKX'; Result = '실패'; Reason = 'Sandbox 에 Store 가 없다' }
@{
    Items = @(
    )
}
```

스키마: `Key = 'Id'`, `Required = @('Id','Result','Reason')`, `Allowed = @('Id','Result','Reason')`, `Enums = @{ Result = @('건너뜀','실패','할 일') }`.

## 동작 명세

### 정상 경로

**`Get-SetupItems`**: `$script:DefaultStageProviders` 를 차례로 부른다. `DeclarationException` 을 던진 단계가 있어도 나머지를 불러 문제를 모은 뒤, 문제가 있으면 모은 문제로 `DeclarationException` 하나를 던진다. 없으면 모든 항목을 돌려준다.

**`Test-SandboxRun`** 판정 규칙. 불합격 이유와 경고는 아래 문구 그대로 쓴다.

1. `Run.Error` 가 비어 있지 않으면 불합격 `Sandbox 안 스크립트 오류: <Error>`.
2. `bootstrap`·`setup-1`·`setup-2` 가 이 순서로 있어야 한다. 없거나 `Result` 가 `null` 이면 불합격 `<Name> 결과 없음 (종료 코드 <ExitCode>)`(실행 자체가 없으면 `(실행 안 됨)`). 종료 코드 2 면 불합격 `<Name> 시작 못 함`.
3. `bootstrap` 의 결과 가운데 `실패`·`할 일` 은 불합격 `[bootstrap] <Id>: <결과 글>`.
4. `setup-1`·`setup-2` 의 결과 하나하나:
   - `Id` 가 예상 결과에 있으면: 실제 결과가 예상 `Result` 와 같으면(예상이 `건너뜀` 이면 `건너뜀`) **예상**으로 세고 넘어간다(`ExpectedHits` +1). 실제가 `그대로`·`바꿈` 이면 경고 `예상 결과 '<Id>' 가 필요 없어 보인다 (<Name> 에서 <결과>)` 를 내고 넘어간다. 그 밖이면 불합격 `[<Name>] [<Stage>] <Id>: <결과 글> (예상 <Result>)`.
   - 예상 결과에 없으면: `setup-1` 은 `실패` 가 불합격, `setup-2` 는 `바꿈`·`실패` 가 불합격(`[<Name>] [<Stage>] <Id>: <결과 글>`). `할 일`·`건너뜀`(사람이 하네스에 준 `-Skip`)은 합격이다.
5. 예상 결과 Id 가 `setup-1` 결과 어디에도 없으면 경고 `예상 결과 '<Id>' 가 셋업 결과에 없다`.
6. 승격 요청: `bootstrap.ElevationRequests + setup-1.ElevationRequests` 가 `$FirstRunElevations` 와 다르면 불합격 `승격 요청 횟수: 첫 실행 <n>회 (기준 <m>회)`. `setup-2.ElevationRequests` 가 `$RerunElevations` 와 다르면 불합격 `승격 요청 횟수: 재실행 <n>회 (기준 <m>회)`. 2 의 불합격으로 결과가 없는 실행은 이 검사를 건너뛴다.
7. `Passed` 는 불합격 이유가 0개일 때 `$true`.

결과 글은 1번 이슈 `Report.psm1` 의 `Format-ResultLine` 과 같은 글 모양(`실패: <원인>` 등)이다. 이 모듈에서 `Report.psm1` 을 불러 써도 된다.

**`Format-SandboxReport`**: 아래 내용을 이 순서로 출력한다. 표의 열 너비는 정하지 않는다.

```
Sandbox 판정: 합격 | 불합격
실행       종료  그대로  바꿈  할 일  실패  건너뜀  승격  시간
bootstrap  0     ...                                1     01:35
setup-1    0     ...                                1     38:10
setup-2    0     ...                                1     06:02
예상 결과로 뺀 결과: <ExpectedHits>개
경고:            (경고가 있을 때만)
  - <경고>
불합격 이유:      (불합격일 때만)
  - <이유>
```

### 엣지 케이스

`Test-SandboxRun` 의 입력 경우를 아래로 한정한다. 각 경우를 테스트로 둔다(입력은 테스트 안에서 만든 객체). **열거하지 않은 경우는 범위 밖이다**(예: `Runs` 순서가 뒤섞인 경우, 같은 Id 가 한 실행에 두 번 나오는 경우).

| # | 입력 | 기대 |
|---|---|---|
| 1 | 세 실행 모두 정상, 첫 실행 `바꿈` 여럿, 재실행 모두 `그대로`, 승격 1·1·1 | 합격 |
| 2 | `Error` 있음 | 불합격 `Sandbox 안 스크립트 오류: …` |
| 3 | `setup-2` 없음 | 불합격 `setup-2 결과 없음 (실행 안 됨)` |
| 4 | `setup-1` 의 `Result` 가 null, 종료 코드 1 | 불합격 `setup-1 결과 없음 (종료 코드 1)` |
| 5 | `setup-1` 종료 코드 2 | 불합격 `setup-1 시작 못 함` |
| 6 | `bootstrap` 의 `clone` 이 `실패: …` | 불합격 |
| 7 | 예상 없음, `setup-1` 에 `실패` | 불합격 |
| 8 | 예상 없음, `setup-2` 에 `바꿈` | 불합격 |
| 9 | 예상 없음, `setup-2` 에 `할 일` | 합격 |
| 10 | 예상 `실패`, 두 실행 모두 `실패` | 합격, `ExpectedHits` 2 |
| 11 | 예상 `건너뜀`, 두 실행 모두 `건너뜀` | 합격 |
| 12 | 예상 `실패`, 실제 `그대로` | 합격 + 경고 `예상 결과 '<Id>' 가 필요 없어 보인다 (...)` |
| 13 | 예상 `할 일`, 실제 `실패` | 불합격 `(예상 할 일)` |
| 14 | 예상 Id 가 결과에 없음 | 경고 `… 셋업 결과에 없다` |
| 15 | 첫 실행 승격 3회 | 불합격 `승격 요청 횟수: 첫 실행 3회 (기준 2회)` |
| 16 | 재실행 승격 0회 | 불합격 `… 재실행 0회 (기준 1회)` |
| 17 | 불합격 이유 여럿 | 모두 `Failures` 에 담김 |

그 밖:

- `Read-SandboxExpected`: 저장소의 `sandbox-expected.psd1` 이 검사를 통과한다. `TestDrive:` 의 파일로 `Result = '그대로'`(허용 값 밖)와 `Reason` 빠짐이 문제가 되는지 본다.
- `Test-SandboxExpectedIds`: 모두 있음 → 빈 배열, 하나 없음 → 문제 하나(줄 번호 포함).
- `Get-SandboxSkipIds`: `건너뜀` 둘·`실패` 하나 → 두 Id.
- `Format-SandboxReport`: 합격·경고 없음 / 불합격·경고 있음, 두 경우의 줄에 `Sandbox 판정:`·`경고:`·`불합격 이유:` 가 있고 없음이 맞다.
- `Get-SetupItems`: 가짜 단계 둘(정상 하나 + `DeclarationException` 하나) → 예외 하나에 문제가 모임. 이 PC 의 실제 `pc-setup` 폴더로 부르면 Windows 설정 11개가 나온다.

### 에러 처리

- `Test-SandboxRun` 은 입력 모양이 어긋나도(속성 없음) 예외를 던지지 않고 불합격 이유로 바꾼다. 범위는 위 표의 경우까지다.

## 기존 코드 참조

- `pc-setup/lib/Declaration.psm1` — `Read-Declaration`, 스키마 모양, `DeclarationException`.
- `pc-setup/lib/Setup.psm1` — `$script:DefaultStageProviders`, `Invoke-Setup` 2단계(선언 검사)의 문제 모으기. `Get-SetupItems` 는 같은 방식으로 모은다.
- `pc-setup/lib/Report.psm1` — `Format-ResultLine`, `mm:ss` 시간 형식.
- `pc-setup/bootstrap.ps1` — 부트스트랩 결과 JSON 의 Stage(`부트스트랩`)와 Id(`winget`·`Git.Git`·`Microsoft.PowerShell`·`clone`).

## 인수 조건

- [ ] `Test-SandboxRun` 표 1~17 과 「그 밖」 목록이 각각 테스트로 있다.
- [ ] 불합격·경고 문구가 명세와 글자까지 같다.
- [ ] `Invoke-Setup` 관련 기존 테스트가 그대로 통과한다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 예상 결과 파일에 근거 없는 줄을 미리 넣는 것(첫 Sandbox 실행 결과로 사람이 채운다).
- 예상 결과 항목을 판정에서 통째로 무시하는 것(허용 결과 밖의 실패는 불합격이고, `그대로` 는 경고다).
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
