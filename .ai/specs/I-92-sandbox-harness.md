> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/92
> updatedAt: 2026-11-11T11:47:17Z

# 호스트 하네스(sandbox.ps1)로 커밋된 HEAD 를 Sandbox 에 넣어 돌리고 판정한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」를 따른다. 이 이슈(부모 [pc-setup 부트스트랩과 Sandbox 하네스](https://github.com/hdmun/anything/issues/88))는 Windows Sandbox 하네스(검증 층 3)를 만든다. 앞 태스크들이 만든 것:

- `pc-setup/bootstrap.ps1` — 부트스트랩(`-Source <bundle>`·`-Skip`·`-ResultPath`·`-SetupResultPath`).
- `pc-setup/test/SandboxJudge.psm1` — 예상 결과 읽기·`Id` 검사·건너뛸 Id·판정·요약 표. `pc-setup/test/sandbox-expected.psd1`. `pc-setup/lib/Setup.psm1` 의 `Get-SetupItems`.
- `pc-setup/test/sandbox-guest.ps1` — Sandbox 안에서 UAC 를 켜고 재시작한 뒤 부트스트랩 → 셋업 재실행을 돌려 `C:\pcs\out\result.json` 을 쓴다. 매핑 폴더 `C:\pcs\in`(읽기 전용: `repo.bundle`·`bootstrap.ps1`·`sandbox-guest.ps1`·`run.psd1`)과 `C:\pcs\out`(쓰기: `state.txt`·`progress.log`·`transcript.txt`·`*.json`·`result.json`)을 쓴다.

이 태스크는 호스트에서 도는 진입점 `pwsh pc-setup/test/sandbox.ps1` 을 만든다. 정한 것([셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「Sandbox 하네스」):

1. `wsb list` 로 Sandbox 가 이미 떠 있는지 본다. 떠 있으면 `실패: Sandbox 사용 중` 을 내고 멈춘다. Sandbox 는 한 번에 하나만 뜨고, relay 세션이 여럿일 수 있다.
2. 커밋된 HEAD 를 `git bundle` 로 묶어 매핑 폴더에 넣고 `.wsb` 를 만들어 Sandbox 를 띄운다. 워크트리의 `.git` 은 호스트 경로를 가리키는 파일이고, 읽기 전용 매핑을 clone 하면 `safe.directory` 소유자 검사에 걸릴 수 있어서 번들을 쓴다. 커밋하지 않은 변경은 시험되지 않는다.
3. 호스트는 `result.json` 을 기다렸다가 **예상 결과**로 판정한다. 요약 표를 출력하고, Sandbox 를 닫고, 종료 코드로 끝난다.
4. 전체 제한은 90분이다. 넘기면 `실패: 시간 초과` 를 내고 Sandbox 를 닫는다. winget 이 프롬프트에 멈춘 경우를 잡으려는 것이다.
5. 로그·결과는 저장소 밖 `$env:TEMP\pc-setup-sandbox\<시각>\` 에 둔다. 커밋하지 않는다. winget 캐시는 쓰지 않는다(부트스트랩의 winget 보장 경로를 그대로 시험한다, 약 300MB).
6. 예상 결과의 `건너뜀` 항목과 사람이 준 `-Skip` 을 합쳐 부트스트랩·셋업에 `-Skip` 으로 넘긴다. 예상 결과의 `Id` 가 선언에 없으면 Sandbox 를 띄우기 전에 멈춘다(셋업이 모르는 `-Skip` Id 로 멈추기 때문이다).

이 PC 에서 확인한 사실(2026-11-11 이 PC 확인): `wsb` 는 `C:\Users\<사용자>\AppData\Local\Microsoft\WindowsApps\wsb.exe`, 버전 `0.8.107.0`. 명령은 `start`(`--config <설정 문자열>`, `--raw`)·`list`(`--raw`)·`stop --id <id>`(id 필수)·`exec`·`share`·`connect`·`ip`. Sandbox 가 없을 때 `wsb list --raw` 출력은 `{ "WindowsSandboxEnvironments": [] }` 다. 떠 있을 때 배열 원소 모양과 `wsb start --raw` 의 출력(id 가 나오는지)은 확인하지 못했다. 구현자가 확인한다. `--config` 가 `.wsb` 파일 내용(XML)을 그대로 받는지도 구현자가 확인한다. 받지 않으면 `ask` 로 묻는다. `wsb exec` 는 출력을 돌려주지 않는다([깨끗한 Windows 에서 셋업 검증하는 방법: Windows Sandbox·VM](https://github.com/hdmun/anything/issues/39)). `git clone <HEAD 만 담은 bundle>` 은 detached HEAD 로 받아진다.

Pester 6.2.0 이 이 PC 에 설치돼 있다. Sandbox 를 실제로 띄우는 것은 게이트가 아니다(부모 「사람이 할 일」). 단위 테스트는 `wsb`·Sandbox 를 `Mock` 으로 바꾸고, git 은 `TestDrive:` 의 작은 저장소로 실제로 시험한다.

## 범위 밖 (건드리지 말 것)

- `bootstrap.ps1`·`sandbox-guest.ps1`·`SandboxJudge.psm1`·`lib/*` 의 동작. 버그를 찾으면 `ask` 로 묻는다.
- 예상 결과 파일의 내용(머지 전 사람이 첫 실행 결과로 채운다).
- Hyper-V VM 검증(층 4).
- 실제 Sandbox 를 띄우는 테스트.

## 변경 대상 파일

- `pc-setup/test/sandbox.ps1` — 신규
- `pc-setup/test/SandboxHost.psm1` — 신규
- `pc-setup/tests/SandboxHost.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/test/sandbox.ps1 (pwsh 7)
#Requires -Version 7
[CmdletBinding()]
param(
    [string[]]$Skip = @(),        # 원소마다 ',' 로 나누고 앞뒤 공백을 뗀다
    [int]$TimeoutMinutes = 90
)
# SandboxHost.psm1 을 불러 Invoke-SandboxHarness 를 부르고 그 종료 코드로 exit 한다.
```

```powershell
# pc-setup/test/SandboxHost.psm1

function Invoke-Wsb { param([string[]]$Arguments) }                  # wsb 를 부르고 표준 출력 문자열을 돌려준다. 종료 코드가 0 이 아니면 예외
function Get-RunningSandboxIds { }                                   # wsb list --raw → id 문자열 배열
function Export-HeadFiles { param([string]$RepoRoot, [string]$InDir) }   # <InDir>\repo.bundle, <InDir>\bootstrap.ps1, <InDir>\sandbox-guest.ps1 (HEAD 의 바이트 그대로)
function New-WsbConfig { param([string]$InDir, [string]$OutDir) }    # → .wsb XML 문자열
function Start-TestSandbox { param([string]$Config) }                # → 새 Sandbox id
function Stop-TestSandbox { param([string]$Id) }
function Wait-SandboxResult { param([string]$OutDir, [TimeSpan]$Timeout, [double]$PollSeconds = 15) }   # result.json 이 생기면 $true, 시간이 다 되면 $false. 기다리는 동안 progress.log 의 새 줄을 출력한다
function Invoke-SandboxHarness {
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [string[]]$Skip = @(),
        [int]$TimeoutMinutes = 90,
        [string]$BaseDir = (Join-Path $env:TEMP 'pc-setup-sandbox')
    )
    # → 종료 코드: 0 합격, 1 불합격(시간 초과 포함), 2 시작 못 함
}

Export-ModuleMember -Function Invoke-Wsb, Get-RunningSandboxIds, Export-HeadFiles, New-WsbConfig, Start-TestSandbox, Stop-TestSandbox, Wait-SandboxResult, Invoke-SandboxHarness
```

`.wsb` 설정(XML, 호스트 경로는 XML 이스케이프):

```xml
<Configuration>
  <MappedFolders>
    <MappedFolder><HostFolder>{InDir}</HostFolder><SandboxFolder>C:\pcs\in</SandboxFolder><ReadOnly>true</ReadOnly></MappedFolder>
    <MappedFolder><HostFolder>{OutDir}</HostFolder><SandboxFolder>C:\pcs\out</SandboxFolder><ReadOnly>false</ReadOnly></MappedFolder>
  </MappedFolders>
  <LogonCommand><Command>powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\pcs\in\sandbox-guest.ps1</Command></LogonCommand>
  <MemoryInMB>8192</MemoryInMB>
</Configuration>
```

## 동작 명세

### 정상 경로

**`Invoke-SandboxHarness`**

1. `Get-RunningSandboxIds` 가 하나라도 있으면 `실패: Sandbox 사용 중` 을 출력하고 2.
2. 작업 트리의 `pc-setup/lib/Setup.psm1`·`pc-setup/test/SandboxJudge.psm1` 을 불러 `Get-SetupItems -Root <RepoRoot>\pc-setup` 로 선언 Id 목록을 얻는다. `DeclarationException` 이면 문제를 모두 출력하고 2. `Read-SandboxExpected`·`Test-SandboxExpectedIds` 의 문제가 있으면 모두 출력하고 2. 사람이 준 `-Skip` 에 선언에 없는 Id 가 있으면 `모르는 -Skip Id: <Id>` 와 2.
3. `git -C <RepoRoot> status --porcelain` 출력이 있으면 `경고: 커밋하지 않은 변경은 시험되지 않는다` 를 출력하고 계속한다.
4. 건너뛸 Id = 예상 결과의 `건너뜀` Id(`Get-SandboxSkipIds`) 다음에 사람의 `-Skip`, 중복은 처음 것만 남긴다.
5. 실행 폴더 `<BaseDir>\<yyyyMMdd-HHmmss>\` 와 그 아래 `in\`·`out\` 을 만든다. `Export-HeadFiles`, `in\run.psd1`(`@{ Skip = @('<Id>', ...) }`, Id 는 작은따옴표 문자열), `New-WsbConfig` 결과를 `<실행 폴더>\sandbox.wsb` 로도 저장한다(다시 띄워 볼 때 쓴다).
6. `Start-TestSandbox` 로 띄우고 `Sandbox 시작: <id>`, `로그: <실행 폴더>` 를 출력한다.
7. `Wait-SandboxResult -Timeout <TimeoutMinutes 분>`. `$false` 면 `실패: 시간 초과 (<TimeoutMinutes>분)` 를 출력하고 1.
8. `out\result.json` 을 읽어 `Test-SandboxRun` → `Format-SandboxReport` 를 출력하고, 같은 줄을 `<실행 폴더>\report.txt` 에도 쓴다. 합격이면 0, 아니면 1. `result.json` 이 JSON 이 아니면 `실패: result.json 을 읽지 못했다` 와 1.
9. 6 에서 Sandbox 를 띄운 뒤에는 어떤 경로로 끝나든(`finally`) `Stop-TestSandbox` 를 한 번 부른다.

**`Export-HeadFiles`**: `git -C <RepoRoot> bundle create <InDir>\repo.bundle HEAD`. 스크립트 두 개는 `git -C <RepoRoot> archive --format=zip -o <임시 zip> HEAD pc-setup/bootstrap.ps1 pc-setup/test/sandbox-guest.ps1` 로 꺼내 압축을 풀고 `<InDir>` 바로 아래에 둔다. 작업 트리 파일을 복사하지 않는다(HEAD 를 시험하고, BOM·줄바꿈 바이트를 그대로 둔다). git 종료 코드가 0 이 아니면 예외.

**`Start-TestSandbox`**: `Invoke-Wsb start --config <Config>` 를 부른 뒤 `Get-RunningSandboxIds` 로 id 를 얻는다(띄우기 전에는 없었으므로 하나뿐이다). `wsb start --raw` 가 id 를 돌려준다는 것을 구현자가 확인했다면 그것을 써도 된다.

**`Wait-SandboxResult`**: `PollSeconds` 마다 `<OutDir>\result.json` 이 있는지 본다. 그 사이 `<OutDir>\progress.log` 에 새로 생긴 줄을 `  [Sandbox] <줄>` 로 한 번씩 출력한다.

### 엣지 케이스

테스트는 `Mock -ModuleName SandboxHost` 로 `Invoke-Wsb`·`Get-RunningSandboxIds`·`Start-TestSandbox`·`Stop-TestSandbox`·`Wait-SandboxResult`(흐름 테스트에서)를 바꾸고, `RepoRoot`·`BaseDir` 는 `TestDrive:` 아래를 쓴다. 흐름 테스트의 `RepoRoot` 는 `TestDrive:` 에 `git init` 한 작은 저장소다(가짜 `pc-setup/lib`·`test` 대신 이 저장소의 실제 모듈을 복사해 쓰거나, `Get-SetupItems`·`Read-SandboxExpected` 를 Mock 한다. 어느 쪽이든 실제 Sandbox·`wsb` 는 부르지 않는다).

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: Sandbox 기능이 꺼진 호스트, 디스크 부족, Sandbox 가 중간에 사람 손으로 닫힌 경우).

| # | 상황 | 기대 |
|---|---|---|
| 1 | Sandbox 가 이미 떠 있음 | 2, `실패: Sandbox 사용 중`, git·`Start-TestSandbox` 안 불림 |
| 2 | 선언 오류 | 2, 문제 출력, `Start-TestSandbox` 안 불림 |
| 3 | 예상 결과 Id 가 선언에 없음 | 2, `sandbox-expected.psd1:<줄>: 선언에 없는 Id '<Id>'` |
| 4 | 모르는 사람 `-Skip` | 2 |
| 5 | 작업 트리에 커밋 안 된 변경 | 경고 출력 후 계속 |
| 6 | 예상 `건너뜀` a + 사람 `-Skip b,a` | `run.psd1` 의 Skip 이 `a`,`b` |
| 7 | 정상, 판정 합격 | 0, `Stop-TestSandbox` 1번, `report.txt` 있음, `sandbox.wsb` 있음 |
| 8 | 판정 불합격 | 1, `Stop-TestSandbox` 1번 |
| 9 | `Wait-SandboxResult` 가 `$false` | 1, `실패: 시간 초과 (90분)`, `Stop-TestSandbox` 1번 |
| 10 | `result.json` 이 깨진 JSON | 1, `실패: result.json 을 읽지 못했다`, `Stop-TestSandbox` 1번 |
| 11 | `Start-TestSandbox` 뒤 예외 | `Stop-TestSandbox` 1번 |

함수 단위:

- `New-WsbConfig`: 결과가 XML 로 파싱되고, `MappedFolder` 둘의 `ReadOnly` 가 `true`/`false`, `SandboxFolder` 가 `C:\pcs\in`/`C:\pcs\out`, `LogonCommand` 가 위 명령이다. 호스트 경로에 `&` 가 있으면 이스케이프된다.
- `Export-HeadFiles`: `TestDrive:` 의 git 저장소에 두 스크립트를 커밋한 뒤 작업 트리에서 내용을 바꿔도, 꺼낸 파일의 바이트가 HEAD 의 것과 같다. `repo.bundle` 을 `git clone` 하면 HEAD 커밋이 나온다.
- `Get-RunningSandboxIds`: `{ "WindowsSandboxEnvironments": [] }` → 빈 배열. 원소가 있는 출력의 모양은 구현자가 실제 `wsb list --raw` 로 확인한 모양을 견본으로 넣는다.
- `Wait-SandboxResult`: 파일이 곧 생김 → `$true`, 안 생김(짧은 Timeout·PollSeconds) → `$false`, `progress.log` 의 줄이 한 번씩만 출력된다.
- `sandbox.ps1`: `-Skip 'a, b'` → `Invoke-SandboxHarness` 가 `@('a','b')` 를 받는다.

### 에러 처리

- 2 단계까지의 오류는 종료 코드 2, Sandbox 를 띄운 뒤의 오류는 1 이다.
- `Stop-TestSandbox` 가 실패하면 경고만 출력하고 종료 코드는 바꾸지 않는다.

## 기존 코드 참조

- `pc-setup/test/SandboxJudge.psm1` — `Read-SandboxExpected`·`Test-SandboxExpectedIds`·`Get-SandboxSkipIds`·`Test-SandboxRun`·`Format-SandboxReport`, `result.json` 모양.
- `pc-setup/test/sandbox-guest.ps1` — 매핑 폴더 경로·`run.psd1`·`progress.log`·`result.json`(임시 파일 뒤 이름 바꿈).
- `pc-setup/lib/Setup.psm1` — `Get-SetupItems`.
- `pc-setup/setup.ps1` — `-Skip` 을 쉼표로 나누는 방식.

## 인수 조건

- [ ] 엣지 케이스 표 1~11 과 함수 단위 목록이 각각 테스트로 있다.
- [ ] 테스트 중 실제 `wsb` 가 불리지 않고 Sandbox 가 뜨지 않는다.
- [ ] 로그·결과를 저장소 안에 쓰지 않는다(기본 `BaseDir` 는 `$env:TEMP\pc-setup-sandbox`).
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 게이트나 테스트에서 실제 Sandbox 를 띄우는 것.
- 작업 트리 파일을 Sandbox 에 넣는 것(HEAD 만 시험한다).
- winget 설치 파일을 호스트에 받아 두고 Sandbox 에 넣는 것(winget 보장 경로를 그대로 시험한다).
- 셋업·부트스트랩에 Sandbox 전용 분기를 넣는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
