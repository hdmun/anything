> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/83
> updatedAt: 2026-11-11T11:47:02Z

# 선언 파일을 실행 없이 읽고 줄 번호와 함께 검사한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**(저장소의 `.psd1` 파일들)대로 맞추는 **셋업** 도구다. 지금 main 에는 뼈대만 있다(`pc-setup/setup.ps1` 이 `-Check` 만 받아 0 으로 끝남). 전체 설계는 부모 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다.

이 태스크는 모든 선언 파일(Windows 설정·앱·설정 파일·저장소 도구)이 함께 쓰는 읽기·검사 모듈을 만든다. 셋업은 UAC 를 묻기 전에 선언의 오타를 잡아야 한다([앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44) 「형식」). 그래서 파일을 **코드 실행 없이** 읽고, 문제가 있으면 줄 번호와 함께 모두 보고한다.

경로 펼치기(`~`·환경 변수)도 여기 둔다. 설정 파일 선언의 `Path` 가 쓴다([설정 파일 관리 방식 정하기: symlink·복사](https://github.com/hdmun/anything/issues/45) 「선언 형식」). 문서 폴더 펼치기는 그것을 쓰던 프로필 항목이 빠져서([에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64)) 만들지 않는다.

Pester 6.2.0 이 이 PC 에 CurrentUser 로 설치돼 있다.

## 범위 밖 (건드리지 말 것)

- 실제 선언 파일(`windows-settings.psd1` 등)과 그 스키마: 각 단계 태스크에서 만든다. 이 태스크의 테스트는 `TestDrive:` 에 만든 선언 파일만 쓴다.
- `pc-setup/setup.ps1`, `pc-setup/tests/Setup.Tests.ps1`: 다음 태스크에서 고친다.
- `pc-setup/CONTEXT.md`.

## 변경 대상 파일

- `pc-setup/lib/Declaration.psm1` — 신규
- `pc-setup/tests/Declaration.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/Declaration.psm1

class DeclarationException : System.Exception {
    [string[]]$Problems   # '<파일 이름>:<줄>: <문제>' 모양
    DeclarationException([string[]]$problems) : base(($problems -join "`n")) { $this.Problems = $problems }
}

function Read-Declaration {
    <# 선언 파일 하나를 실행 없이 읽고 검사한다.
       성공: 항목 [pscustomobject[]] — 선언의 키를 그대로 속성으로 갖고, 더해서 Line(항목 시작 줄 번호, 1부터)을 갖는다.
       문제: 모두 모아 DeclarationException 을 던진다. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Schema
    )
}

function Expand-SetupPath {
    <# '~' 로 시작하면 $HOME 으로, '$env:<이름>' 은 그 환경 변수 값으로 바꾼다. 경로 구분자는 '\' 로 맞춘다. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
}

Export-ModuleMember -Function Read-Declaration, Expand-SetupPath
```

스키마 해시테이블 모양(각 단계 모듈이 이 모양으로 넘긴다):

```powershell
@{
    Key      = 'Id'                         # 중복을 보는 식별 키
    Required = @('Id')                      # 모든 항목에 있어야 하는 키
    Allowed  = @('Id','Path','Name','Type','Value','Script','Elevated')   # 이 밖의 키는 문제
    Enums    = @{ Type = @('DWord','String') }   # 값이 목록 안에 있어야 하는 키(선택)
    Validate = { param($item) }             # 선택. 항목 하나의 추가 문제를 문자열 배열로 돌려준다(없으면 빈 배열)
}
```

## 동작 명세

### 정상 경로

**`Read-Declaration`**

1. `[System.Management.Automation.Language.Parser]::ParseFile` 로 파싱한다. 파싱 오류가 있으면 오류마다 `<파일 이름>:<줄>: 문법 오류: <메시지>` 문제를 만들고 바로 던진다.
2. 최상위는 해시테이블 하나이고 키는 `Items` 하나다. `Items` 값은 해시테이블들의 배열(`@( ... )`)이다. 모양이 다르면 `<파일 이름>:1: 최상위는 @{ Items = @( ... ) } 이어야 한다` 문제를 던진다.
3. 항목 해시테이블마다 `SafeGetValue()` 로 값을 얻는다(변수·명령이 들어 있으면 실패한다 → 그 항목에 `값에 식이 들어 있다` 문제). 줄 번호는 그 항목 해시테이블 AST 의 `Extent.StartLineNumber` 다.
4. 항목마다 스키마로 검사한다(아래 문제 문구). 모든 항목의 모든 문제를 모은다.
5. 문제가 없으면 항목을 선언 순서대로 돌려준다. 항목 객체의 속성 순서는 선언의 키 순서이고 마지막에 `Line` 이 붙는다.

문제 문구(`<파일 이름>` 은 `Split-Path -Leaf`, 문구는 그대로 쓴다):

| 경우 | 문제 |
|---|---|
| 모르는 키 | `<파일 이름>:<줄>: 모르는 키 '<키>'` |
| 빠진 필수 키 | `<파일 이름>:<줄>: 필수 키 '<키>' 가 없다` |
| 중복 식별 키 | `<파일 이름>:<줄>: '<Key>' 값 '<값>' 이 <첫 줄>번 줄과 겹친다` (두 번째 이후 항목마다) |
| 허용 값 밖 | `<파일 이름>:<줄>: '<키>' 값 '<값>' 은 허용되지 않는다 (허용: <값1>, <값2>)` |
| `Validate` 가 돌려준 문자열 s | `<파일 이름>:<줄>: <s>` |

키 비교는 대소문자를 구분한다(`id` 는 모르는 키다). 오타를 잡기 위해서다.

**`Expand-SetupPath`**

- `~` 또는 `~/`·`~\` 로 시작하면 그 부분을 `$HOME` 으로 바꾼다. 중간의 `~` 는 그대로 둔다.
- `$env:<이름>`(이름은 `[A-Za-z_][A-Za-z0-9_]*`)을 모두 그 환경 변수 값으로 바꾼다. 환경 변수가 없으면 예외 `환경 변수 '<이름>' 이 없다` 를 던진다.
- `/` 를 `\` 로 바꾼다.
- 예: `~/.nanorc` → `C:\Users\me\.nanorc`, `$env:LOCALAPPDATA/Packages/x/settings.json` → `C:\Users\me\AppData\Local\Packages\x\settings.json`.

### 엣지 케이스

`Read-Declaration` 의 입력 경우를 아래로 한정한다. 각 경우를 테스트 하나 이상으로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 중첩 해시테이블 값, 여러 줄에 걸친 항목의 줄 번호 규칙). 범위 밖 경우의 결과는 테스트하지 않는다.

| # | 입력 | 결과 |
|---|---|---|
| 1 | 정상 파일, 항목 3개, 주석 줄 있음 | 항목 3개, 각 `Line` 이 실제 줄 번호 |
| 2 | `Items = @()` | 빈 배열, 문제 없음 |
| 3 | 닫는 괄호 빠짐 | `문법 오류` 문제 |
| 4 | 최상위에 `Items` 대신 `Apps` | 최상위 모양 문제 |
| 5 | 항목에 모르는 키 | 모르는 키 문제, 줄 번호 맞음 |
| 6 | 필수 키 빠짐 | 필수 키 문제 |
| 7 | 같은 `Id` 두 항목(2번째 줄·5번째 줄) | 5번째 줄에 「2번 줄과 겹친다」 |
| 8 | 열거형 키 값이 목록 밖 | 허용 값 문제(허용 값 나열) |
| 9 | 값에 식(큰따옴표 `"$env:X"`, `$(...)`, 변수 `$x`) | 「값에 식이 들어 있다」. 작은따옴표 `'$env:X'` 는 글자 그대로의 문자열이라 문제가 아니다 |
| 10 | 한 파일에 문제 3개(서로 다른 줄) | 예외 하나에 `Problems` 3개 |
| 11 | `Validate` 가 문자열 하나 돌려줌 | 그 문자열이 줄 번호와 함께 문제로 |
| 12 | 키 대소문자 다름(`id`) | 모르는 키 + 빠진 필수 키 |

`Expand-SetupPath`: `~` 시작, `~` 중간, `$env:` 하나·둘, 없는 환경 변수, `/` 섞임 — 각각 테스트로 둔다.

### 에러 처리

- 파일이 없으면 `DeclarationException`(`<파일 이름>:0: 파일이 없다`)을 던진다.
- `Read-Declaration` 은 화면에 아무것도 출력하지 않는다. 출력은 셋업이 한다.

## 기존 코드 참조

- `pc-setup/setup.ps1`, `pc-setup/tests/Setup.Tests.ps1` — 지금의 뼈대. 테스트 파일 모양(`Describe`/`It`, `$PSScriptRoot` 기준 경로)을 따른다.
- `agent-accounts/AgentAccounts.ps1` — 이 저장소의 `.psd1` 읽기 예(`Import-PowerShellDataFile`). 이 태스크는 줄 번호가 필요해서 AST 로 읽는다.

## 인수 조건

- [ ] 엣지 케이스 표 1~12 와 `Expand-SetupPath` 경우가 각각 테스트로 있다.
- [ ] 문제 문구가 위 표와 글자까지 같다.
- [ ] `Read-Declaration` 이 선언 파일 안의 코드를 실행하지 않는다(테스트: 값에 `$(New-Item ...)` 를 넣은 파일을 읽어도 파일이 생기지 않고 「값에 식이 들어 있다」가 나온다).
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- `Import-PowerShellDataFile`·`Invoke-Expression`·dot-source 로 선언을 읽는 것(줄 번호가 없거나 코드를 실행한다).
- 첫 문제에서 멈추는 것. 문제는 모두 모은다(문법 오류만 예외).
- 테스트를 건너뛰게 만드는 것(`-Skip`, 조건부 `return`), 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
