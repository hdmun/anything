> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/84
> updatedAt: 2026-11-11T11:47:04Z

# 결과 줄·끝 요약·종료 코드와 항목 스크립트 실행 규칙을 만든다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 전체 설계는 부모 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다. 앞 태스크가 `pc-setup/lib/Declaration.psm1`(선언 읽기·검사)을 만들었다.

셋업의 모든 단계(Windows 설정·앱·설정 파일·저장소 도구)는 항목마다 결과 하나를 내고, 셋업은 끝에 요약과 종료 코드를 낸다. 결과 말은 `그대로`·`바꿈`·`할 일`·`실패`(고치는 실행)와 `그대로`·`다름`·`할 일`·`확인 못 함`·`실패`(`-Check`), 그리고 `-Skip` 의 `건너뜀` 이다([셋업이 저장소 도구를 설치하는 방식 정하기](https://github.com/hdmun/anything/issues/41) 「`install.ps1` 계약」, [부트스트랩 진입점과 관리자 권한 처리 정하기](https://github.com/hdmun/anything/issues/42) 「UAC·`-Check`·재부팅」, [셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「셋업·부트스트랩에 더하는 것」).

또 여러 단계가 「항목 스크립트」(`windows/<Id>.ps1`·`apps/<Id>.ps1`·도구 폴더의 `install.ps1`)를 부른다. 스크립트는 마지막 출력 줄로 결과를 알린다. 이 태스크는 그 줄을 읽어 결과로 바꾸는 실행기를 만든다.

이 태스크는 순수 로직 두 모듈이다. 셋업 흐름(`Invoke-Setup`)은 다음 태스크가 이 모듈을 써서 만든다.

## 범위 밖 (건드리지 말 것)

- `pc-setup/setup.ps1`, `pc-setup/lib/Setup.psm1`, 승격 단계: 다음 태스크.
- 실제 항목 스크립트(`windows/*.ps1` 등): 뒤 태스크. 이 태스크의 테스트는 `TestDrive:` 에 만든 가짜 스크립트를 쓴다.
- `pc-setup/lib/Declaration.psm1`.

## 변경 대상 파일

- `pc-setup/lib/Report.psm1` — 신규
- `pc-setup/lib/ItemScript.psm1` — 신규
- `pc-setup/tests/Report.Tests.ps1` — 신규
- `pc-setup/tests/ItemScript.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/Report.psm1

function New-SetupResult {
    # → [pscustomobject]@{ Stage; Id; Status; Detail }
    param(
        [Parameter(Mandatory)][string]$Stage,
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][ValidateSet('그대로','바꿈','할 일','실패','다름','확인 못 함','건너뜀')][string]$Status,
        [string]$Detail = ''
    )
}

function ConvertFrom-ResultText {
    # 결과 글 한 줄('바꿈 (백업: x)', '할 일: 재부팅 후 셋업 다시 실행' 등) → @{ Status; Detail }
    # 모양이 맞지 않으면 $null.
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [switch]$Check)
}

function Format-ResultLine {
    # 결과 → '[<Stage>] <Id>: <결과 글>'
    param([Parameter(Mandatory)]$Result)
}

function Format-SetupSummary {
    # → 끝 요약 줄들 [string[]]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results,
        [int]$ElevationRequests = 0,
        [TimeSpan]$Duration = [TimeSpan]::Zero,
        [switch]$Check
    )
}

function Get-SetupExitCode {
    # 실패 0개 → 0, 1개 이상 → 1
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Results)
}

Export-ModuleMember -Function New-SetupResult, ConvertFrom-ResultText, Format-ResultLine, Format-SetupSummary, Get-SetupExitCode
```

```powershell
# pc-setup/lib/ItemScript.psm1

function Invoke-ItemScript {
    # 항목 스크립트를 같은 프로세스에서 부르고 마지막 출력 줄을 결과로 바꾼다 → @{ Status; Detail }
    param([Parameter(Mandatory)][string]$Path, [switch]$Check)
}

Export-ModuleMember -Function Invoke-ItemScript
```

## 동작 명세

### 정상 경로

**결과 글 모양** (`ConvertFrom-ResultText` 와 `Format-ResultLine` 이 서로 반대다)

| 결과 | 글 | Detail |
|---|---|---|
| 그대로 | `그대로` | 빈 문자열 |
| 바꿈 | `바꿈` 또는 `바꿈 (<설명>)` | 설명 |
| 다름 | `다름` 또는 `다름 (<설명>)` | 설명 |
| 할 일 | `할 일: <할 일>` | 할 일 |
| 실패 | `실패: <원인>` | 원인 |
| 확인 못 함 | `확인 못 함: <이유>` | 이유 |
| 건너뜀 | `건너뜀` | 빈 문자열 |

- `ConvertFrom-ResultText` 는 앞뒤 공백을 떼고 위 모양에 맞춘다. `-Check` 가 아니면 `다름`·`확인 못 함` 은 `$null`, `-Check` 면 `바꿈` 은 `$null` 이다. `할 일:`·`실패:`·`확인 못 함:` 뒤가 비어 있으면 `$null` 이다. `건너뜀` 은 셋업만 만드는 결과라 항목 스크립트 글로는 받지 않는다(`$null`).
- `Format-ResultLine`: `[<Stage>] <Id>: <글>`. 예: `[Windows 설정] LongPaths: 그대로`, `[앱] wsl: 할 일: 재부팅 후 셋업 다시 실행`.

**`Format-SetupSummary`**

```
요약: 그대로 12 · 바꿈 3 · 할 일 1 · 실패 0 · 건너뜀 0
승격 요청: 1회
걸린 시간: 04:12
할 일:
  - 재부팅 후 셋업 다시 실행 (wsl, Hibernate)
실패:
  - [앱] Foo: <원인>
```

- 요약 줄 순서: 고치는 실행은 `그대로 · 바꿈 · 할 일 · 실패 · 건너뜀`, `-Check` 는 `그대로 · 다름 · 할 일 · 확인 못 함 · 실패 · 건너뜀`. 0 개도 적는다. 구분자는 ` · `(가운뎃점 앞뒤 공백)이다.
- `걸린 시간` 은 `mm:ss`, 1시간 이상이면 `h:mm:ss` 다.
- `할 일:` 블록: `할 일` 결과가 있을 때만. 같은 Detail 은 한 줄로 모으고 괄호에 Id 를 처음 나온 순서대로 `, ` 로 잇는다.
- `실패:` 블록: `실패` 결과가 있을 때만. 결과마다 한 줄 `  - [<Stage>] <Id>: <Detail>`.

### 엣지 케이스

`ConvertFrom-ResultText` 의 입력 경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 여러 줄 글, 전각 콜론).

| # | 입력 | `-Check` | 결과 |
|---|---|---|---|
| 1 | `그대로` | 둘 다 | 그대로 |
| 2 | `바꿈` / `바꿈 (백업: C:\a.bak)` | 아님 | 바꿈, Detail 빈 값 / `백업: C:\a.bak` |
| 3 | `바꿈` | 예 | `$null` |
| 4 | `다름 (값 0, 선언 1)` | 예 | 다름, Detail `값 0, 선언 1` |
| 5 | `다름` | 아님 | `$null` |
| 6 | `할 일: 재부팅 후 셋업 다시 실행` | 둘 다 | 할 일 |
| 7 | `실패: 접근 거부` | 둘 다 | 실패 |
| 8 | `확인 못 함: 관리자 필요` | 예 | 확인 못 함 |
| 9 | `할 일:` (뒤가 빔) | 둘 다 | `$null` |
| 10 | `  그대로  ` (앞뒤 공백) | 둘 다 | 그대로 |
| 11 | `OK`, 빈 문자열 | 둘 다 | `$null` |
| 12 | `건너뜀` | 둘 다 | `$null` |

**`Invoke-ItemScript`** (가짜 스크립트를 `TestDrive:` 에 만들어 시험한다)

| # | 스크립트 | 결과 |
|---|---|---|
| 1 | `Write-Output '그대로'` | 그대로 |
| 2 | 여러 줄 출력 뒤 마지막 줄 `바꿈 (x)` | 바꿈, Detail `x` (앞 줄은 무시) |
| 3 | `-Check` 를 받아 `다름` 을 낸다 | `-Check` 로 부르면 다름 |
| 4 | 출력 없음 | 실패, Detail `결과 줄 없음` |
| 5 | 마지막 줄이 `OK` | 실패, Detail `모르는 결과: OK` |
| 6 | `throw '디스크 가득'` | 실패, Detail `디스크 가득` |
| 7 | 파일이 없음 | 실패, Detail `스크립트가 없다: <경로>` |
| 8 | 마지막 출력이 문자열이 아닌 객체 뒤 문자열 | 마지막 **문자열** 줄을 쓴다 |
| 9 | 스크립트가 `exit 3` 으로 끝나고 그 앞에 `실패: x` 출력 | 실패, Detail `x` (종료 코드로 판정하지 않는다) |

- 부를 때 `-Check` 를 넘기면 `& $Path -Check`, 아니면 `& $Path` 다. 스크립트의 `Write-Host`·정보 스트림은 그대로 화면에 둔다. 결과는 출력 스트림(성공 스트림)의 마지막 문자열 줄만 본다.
- `Get-SetupExitCode`: 빈 목록 → 0, `실패` 1개 → 1, `할 일`·`다름`·`확인 못 함` 만 → 0.

### 에러 처리

- 두 모듈은 화면에 쓰지 않는다(문자열을 돌려줄 뿐). 예외는 `Invoke-ItemScript` 가 잡아 결과로 바꾼다.

## 기존 코드 참조

- `pc-setup/lib/Declaration.psm1` — 앞 태스크가 만든 모듈. 모듈 모양(`Export-ModuleMember`)을 맞춘다.
- `pc-setup/tests/Declaration.Tests.ps1` — 테스트에서 모듈을 불러오는 방식(`Import-Module (Join-Path $PSScriptRoot '..' 'lib' '<이름>.psm1') -Force`)을 맞춘다.
- `rdp-notify/register.ps1` — 뒤 이슈에서 `install.ps1` 이 감쌀 기존 스크립트. 결과 줄 규칙이 왜 필요한지 보여 준다(수정하지 않는다).

## 인수 조건

- [ ] `ConvertFrom-ResultText` 표 1~12, `Invoke-ItemScript` 표 1~9 가 각각 테스트로 있다.
- [ ] `Format-ResultLine (ConvertFrom-ResultText 로 만든 결과)` 가 원래 글로 돌아온다(그대로·바꿈 (x)·할 일: x·실패: x·다름 (x)).
- [ ] `Format-SetupSummary` 의 고치는 실행·`-Check`·할 일 모음·실패 블록·1시간 넘는 시간이 테스트로 있다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 결과 말을 늘리거나 바꾸는 것(위 7개만).
- 항목 스크립트를 자식 프로세스(`pwsh -File`)로 부르는 것. 같은 프로세스에서 부른다.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
