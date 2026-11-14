> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/91
> updatedAt: 2026-11-11T11:47:16Z

# Sandbox 안에서 UAC 를 켜고 부트스트랩·셋업 재실행을 돌려 result.json 을 쓰는 스크립트를 만든다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」를 따른다. 이 이슈(부모 [pc-setup 부트스트랩과 Sandbox 하네스](https://github.com/hdmun/anything/issues/88))는 Windows Sandbox 하네스(검증 층 3)를 만든다. 앞 태스크들이 `pc-setup/bootstrap.ps1`(부트스트랩)과 `pc-setup/test/SandboxJudge.psm1`(판정, `result.json` 모양 정의)을 만들었다.

이 태스크는 **Sandbox 안에서** 도는 스크립트 `pc-setup/test/sandbox-guest.ps1` 을 만든다. 호스트 하네스(다음 태스크)가 이 스크립트를 `.wsb` 의 `LogonCommand` 로 걸어 Sandbox 를 띄운다. 정한 것과 확인한 사실([셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「Sandbox 하네스」·「확인한 사실」, [깨끗한 Windows 에서 셋업 검증하는 방법: Windows Sandbox·VM](https://github.com/hdmun/anything/issues/39)):

- Sandbox 사용자 `WDAGUtilityAccount` 는 기본으로 High 권한이고 UAC 가 꺼져 있다(`EnableLUA=0`). 그대로는 일반 권한 창을 얻을 수 없어 셋업이 「관리자 창이면 멈춤」에 걸린다.
- 첫 로그온에서 `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` 의 `EnableLUA=1`, `ConsentPromptBehaviorAdmin=0`(확인 창 없이 승격)으로 바꾸고 재시작하면 값이 남는다. 재시작 뒤 `LogonCommand` 가 **다시 돌고** Medium(일반 권한)으로 돈다. 매핑 폴더도 남는다. `Start-Process -Verb RunAs` 는 확인 창 없이 High 로 뜬다. 재시작은 약 49초 걸렸다.
- Sandbox 에는 winget·git·pwsh 가 없다. Windows PowerShell 5.1 만 있다. 실행 정책은 Process=Bypass, 나머지 범위는 Undefined 다.
- 그래서 이 스크립트는 5.1 에서 돌고, 같은 스크립트가 두 번(재시작 앞뒤) 불린다. 어느 차례인지는 쓰기 가능한 매핑 폴더의 상태 파일로 안다.
- 셋업·부트스트랩 코드는 Sandbox 를 모른다. Sandbox 에만 필요한 일(UAC 켜기, 결과 모으기)은 이 스크립트가 한다.

매핑 폴더(다음 태스크의 호스트가 만든다):

| Sandbox 안 경로 | 읽기 전용 | 내용 |
|---|---|---|
| `C:\pcs\in` | 예 | `repo.bundle`(커밋된 HEAD), `bootstrap.ps1`, `sandbox-guest.ps1`(둘 다 HEAD 의 것), `run.psd1`(`@{ Skip = @('<Id>', ...) }`) |
| `C:\pcs\out` | 아니오 | 이 스크립트가 쓰는 상태·로그·결과 |

5.1 제약: 파일을 `-File` 로 읽을 때 BOM 없는 UTF-8 은 cp949 로 읽힌다. `ConvertTo-Json` 의 기본 깊이는 2 다. pwsh 7 전용 문법(`??`, 삼항 등)을 쓸 수 없다.

Pester 6.2.0 이 이 PC 에 설치돼 있다(pwsh 7). 이 스크립트의 실제 동작은 Sandbox 전체 실행(부모 「사람이 할 일」)이 본다. 게이트는 단위 테스트와 5.1 파싱 검사다.

## 범위 밖 (건드리지 말 것)

- 호스트 쪽(`.wsb` 만들기·Sandbox 띄우기·기다리기·판정 출력): 다음 태스크.
- `bootstrap.ps1`·`setup.ps1`·`lib/*`·`SandboxJudge.psm1` 의 동작. 버그를 찾으면 `ask` 로 묻는다.
- Sandbox 안에서 재부팅이 필요한 항목(WSL 등)을 이어서 돌리는 것. 셋업 중 재시작은 오류로 본다.

## 변경 대상 파일

- `pc-setup/test/sandbox-guest.ps1` — 신규 (UTF-8 **BOM 있음**)
- `pc-setup/tests/SandboxGuest.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/test/sandbox-guest.ps1 — Windows PowerShell 5.1
[CmdletBinding()]
param(
    [string]$InDir = 'C:\pcs\in',
    [string]$OutDir = 'C:\pcs\out'
)

function Test-AdminWindow { }                                         # → [bool]
function Enable-TestUac { }                                           # EnableLUA=1, ConsentPromptBehaviorAdmin=0 (HKLM Policies\System)
function Restart-Guest { }                                            # Restart-Computer -Force
function Invoke-Child { param([string]$FilePath, [string[]]$Arguments) }   # 자식 프로세스를 기다려 종료 코드를 돌려준다
function Update-SessionPath { }                                       # 세션 PATH 를 Machine + User 레지스트리 값으로 다시 읽는다
function Get-GuestRepoPath { }                                        # 사용자 환경 변수 ANYTHING_REPO, 없으면 "$HOME\anything"
function Write-GuestProgress { param([string]$OutDir, [string]$Message) }   # <OutDir>\progress.log 에 '<yyyy-MM-dd HH:mm:ss> <Message>' 한 줄 추가
function Read-JsonOrNull { param([string]$Path) }                     # 파일이 있고 JSON 이면 객체, 아니면 $null
function Write-GuestResult { param([string]$OutDir, $Result) }        # <OutDir>\result.json.tmp 에 쓰고 result.json 으로 이름 바꿈(ConvertTo-Json -Depth 20, UTF-8)
function Invoke-Guest { param([string]$InDir, [string]$OutDir) }

# 맨 아래 본문 (이 한 줄만)
Invoke-Guest -InDir $InDir -OutDir $OutDir
```

상태 파일 `<OutDir>\state.txt` 값: 없음 → `uac` → `running` → `done`.

`result.json` 모양은 `SandboxJudge.psm1` 이 정한 것 그대로다: `{ Error, Runs: [ { Name, ExitCode, Result } ] }`, `Name` 은 `bootstrap`·`setup-1`·`setup-2`.

## 동작 명세

### 정상 경로

**`Invoke-Guest`** 는 상태 파일을 읽고 그 값에 따라 한 가지만 한다.

1. **상태 없음** (첫 로그온): `Write-GuestProgress 'UAC 켜고 재시작'` → `Enable-TestUac` → 상태 `uac` → `Restart-Guest`.
2. **상태 `uac`** (재시작 뒤):
   1. `Test-AdminWindow` 가 `$true` 면 `Error = 'UAC 를 켠 뒤에도 관리자 권한으로 돈다'` 로 결과를 쓰고 상태 `done`.
   2. 상태 `running`. `Start-Transcript <OutDir>\transcript.txt`.
   3. `<InDir>\run.psd1` 을 `Import-PowerShellDataFile` 로 읽어 `Skip` 을 얻는다.
   4. `Write-GuestProgress 'bootstrap 시작'` → `Invoke-Child powershell.exe -NoProfile -ExecutionPolicy Bypass -File <InDir>\bootstrap.ps1 -Source <InDir>\repo.bundle -ResultPath <OutDir>\bootstrap.json -SetupResultPath <OutDir>\setup-1.json` (`Skip` 이 있으면 `-Skip <쉼표로 이은 Id>` 추가) → `Write-GuestProgress 'bootstrap 끝 (<종료 코드>)'`. Runs 에 `bootstrap`(Result = `bootstrap.json`)을 넣는다. `setup-1.json` 이 있으면 `setup-1`(ExitCode = 부트스트랩 종료 코드, 부트스트랩은 셋업 종료 코드를 그대로 돌려준다)도 넣는다.
   5. `setup-1.json` 이 있을 때만: `Update-SessionPath` → `Write-GuestProgress 'setup-2 시작'` → `Invoke-Child pwsh -NoProfile -File <Get-GuestRepoPath>\pc-setup\setup.ps1 -ResultPath <OutDir>\setup-2.json` (`Skip` 이 있으면 `-Skip` 추가) → `Write-GuestProgress 'setup-2 끝 (<종료 코드>)'`. Runs 에 `setup-2` 를 넣는다. `pwsh` 를 찾지 못하면 `$env:ProgramFiles\PowerShell\7\pwsh.exe` 를 쓴다.
   6. `Write-GuestResult`(Error 빈 문자열) → `Stop-Transcript` → 상태 `done` → `Write-GuestProgress '끝'`.
3. **상태 `running`** (셋업 중 재시작됨): `Error = '셋업 중 Sandbox 가 다시 시작됐다'` 로 결과를 쓰고 상태 `done`.
4. **상태 `done`**: 아무것도 하지 않는다.

- 2 의 어느 단계에서든 예외가 나면 그때까지 모은 Runs 와 `Error = <예외 메시지>` 로 결과를 쓰고 상태 `done` 으로 끝난다. 결과 파일은 반드시 한 번 쓴다. 호스트는 `result.json` 이 생기기를 기다리기 때문이다.
- `Write-GuestResult` 는 임시 파일에 다 쓴 뒤 이름을 바꾼다. 호스트가 반쯤 쓴 파일을 읽지 않게 하려는 것이다.

### 엣지 케이스

테스트 방식: 부트스트랩 태스크와 같다. Pester(pwsh 7)에서 파서로 `sandbox-guest.ps1` 의 함수 정의만 꺼내 정의하고, 바깥 동작 함수(`Test-AdminWindow`·`Enable-TestUac`·`Restart-Guest`·`Invoke-Child`·`Update-SessionPath`·`Get-GuestRepoPath`)를 `Mock` 한 뒤 `Invoke-Guest -InDir <TestDrive 폴더> -OutDir <TestDrive 폴더>` 를 부른다. `Invoke-Child` 의 가짜는 인자에서 `-ResultPath`·`-SetupResultPath` 를 찾아 JSON 을 써서 실제 실행을 흉내 낸다.

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 매핑 폴더가 없는 경우, 디스크 가득).

| # | 상황 | 기대 |
|---|---|---|
| 1 | 상태 없음 | `Enable-TestUac`·`Restart-Guest` 각 1번, 상태 `uac`, `Invoke-Child` 안 불림, `result.json` 없음 |
| 2 | 상태 `uac`, 관리자 아님, 부트스트랩·셋업 모두 JSON 씀 | `Invoke-Child` 2번, `result.json` 의 Runs 3개(이름 순서), Error 빈 값, 상태 `done` |
| 3 | 2 + `run.psd1` 의 Skip 2개 | 두 `Invoke-Child` 인자에 `-Skip` 과 `a,b` |
| 4 | 2 + Skip 없음 | 인자에 `-Skip` 없음 |
| 5 | 상태 `uac`, 관리자 | Error `UAC 를 켠 뒤에도 관리자 권한으로 돈다`, `Invoke-Child` 안 불림 |
| 6 | 부트스트랩이 `setup-1.json` 을 쓰지 않음(종료 코드 1) | Runs 에 `bootstrap` 하나, `setup-2` 안 돎 |
| 7 | 부트스트랩이 `bootstrap.json` 도 쓰지 않음 | `bootstrap` 의 Result null |
| 8 | `Invoke-Child` 가 예외 | Error 에 메시지, `result.json` 있음, 상태 `done` |
| 9 | 상태 `running` | Error `셋업 중 Sandbox 가 다시 시작됐다` |
| 10 | 상태 `done` | 아무 함수도 안 불림, `result.json` 을 다시 쓰지 않음 |
| 11 | 2 의 `progress.log` | `bootstrap 시작`·`bootstrap 끝 (0)`·`setup-2 시작`·`setup-2 끝 (0)`·`끝` 줄이 순서대로 |
| 12 | 2 의 `result.json` 을 `Test-SandboxRun` 에 넣음 | 예외 없이 판정이 나온다(모양 호환) |

5.1 호환 테스트(부트스트랩 태스크와 같은 방식): `powershell.exe` 의 파서로 오류 0개, 파일 첫 3바이트가 UTF-8 BOM.

### 에러 처리

- `Restart-Guest` 뒤에는 아무것도 하지 않는다(재시작이 스크립트를 끊는다).
- 결과 파일 쓰기 자체가 실패하면 할 수 있는 것이 없다. 예외를 그대로 둔다(호스트가 90분 제한으로 잡는다).

## 기존 코드 참조

- `pc-setup/bootstrap.ps1` — 인자(`-Source`·`-Skip`·`-ResultPath`·`-SetupResultPath`), 함수 정의만 꺼내 시험하는 방식, BOM 규칙.
- `pc-setup/tests/Bootstrap.Tests.ps1` — 함수 정의를 꺼내는 테스트 도우미. 같은 방식을 쓴다(도우미를 복사하지 말고 공유가 필요하면 `ask` 로 묻는다).
- `pc-setup/test/SandboxJudge.psm1` — `result.json` 모양, `Test-SandboxRun`.
- `pc-setup/setup.ps1` — `-Skip`·`-ResultPath`.

## 인수 조건

- [ ] 엣지 케이스 표 1~12 와 5.1 호환 테스트가 각각 테스트로 있다.
- [ ] 테스트 중 실제 레지스트리·재시작·자식 프로세스가 불리지 않는다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC(호스트)에서 `sandbox-guest.ps1` 을 실행하는 것. UAC 정책을 바꾸고 재시작한다.
- 셋업이나 부트스트랩에 Sandbox 전용 분기를 넣는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
