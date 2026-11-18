> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/97
> updatedAt: 2026-11-17T11:56:36Z

# nvm·pnpm·go 원천으로 Node 줄과 전역 패키지를 맞춘다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. 부모 이슈 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)의 첫 태스크가 앱 단계 골격(`lib/Apps.psm1`)을 만들었다. `pc-setup/lib/AppRuntime.psm1` 의 `Invoke-NvmApp`·`Invoke-PnpmApp`·`Invoke-GoApp` 은 지금 `throw '아직 구현되지 않은 원천: <원천>'` 이다. 이 태스크가 셋을 채운다.

**런타임**이 설치한 명령으로 받는 **원천** 셋이다.

| 원천 | 선언 줄 | 정한 곳 |
|---|---|---|
| nvm | `@{ Id = 'node'; Origin = 'nvm'; NodeLine = '26' }` | [런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62) 「Node: nvm v2」 |
| pnpm | `@{ Id = '@openai/codex'; Origin = 'pnpm' }` | [런타임 전역 패키지 선언 정하기](https://github.com/hdmun/anything/issues/67) 「원천 pnpm」 |
| go | `@{ Id = 'golang.org/x/tools/gopls'; Origin = 'go' }`, `@{ Id = 'honnef.co/go/tools/cmd/staticcheck'; Origin = 'go' }` | 같은 티켓 「원천 go」 |

선언 순서(마지막 태스크가 `apps.psd1` 에 이 순서로 쓴다): scoop `nvm` → `node`(nvm) → winget `pnpm.pnpm` → pnpm 원천 항목, winget `GoLang.Go` → go 원천 항목. 모두 일반 권한이다. 버전은 고정하지 않는다(Node 는 **버전 줄**만). 업그레이드는 셋업 밖이다.

같은 셋업 실행 안에서 앞 항목(scoop nvm, winget pnpm·Go)이 방금 설치한 명령을 써야 한다. 또 `GoLang.Go` 는 승격 단계(다른 프로세스)에서 설치된다. 그래서 세 함수는 명령을 찾기 전에 `Update-SessionPath`(`lib/EnvPath.psm1`)를 부른다.

이 PC 에서 확인한 사실(2026-11-11):

- `nvm` 은 nvm-windows **v1** 1.2.2(`%LOCALAPPDATA%\nvm\nvm.exe`)이다. `nvm version` 이 `1.2.2` 를 출력한다. Node 23.3.0 하나만 있다. v2 는 이 PC 에 없다.
- pnpm 은 단독 설치본 10.33.2(`%LOCALAPPDATA%\pnpm\pnpm.CMD`), `PNPM_HOME` = `%LOCALAPPDATA%\pnpm` 이다. 전역 패키지가 없을 때 `pnpm ls -g --json` 출력은 `[ { "path": "...\\pnpm\\global\\5", "private": false } ]` 로 `dependencies` 키가 없다.
- `go env GOPATH` = `C:\Users\hdmun\go`. `~/go/bin` 에 `gopls.exe`·`staticcheck.exe` 가 있다.

## 범위 밖 (건드리지 말 것)

- nvm v1 → v2 이전, pnpm 단독 설치본 정리, npm 전역 패키지: 셋업이 하지 않는다. 6번 구현 이슈의 검증 PC 체크리스트가 다룬다([집의 다른 PC 로 셋업을 검증하는 방식 정하기](https://github.com/hdmun/anything/issues/71) 「셋업 전 정리」).
- nvm v2 `auto_installed_modules`, pnpm 빌드 스크립트 허용(`AllowBuild`) 키: 쓰지 않는다(#67).
- 남은 다른 Node 줄: 셋업이 모른다([선언에 없는 앱(드리프트) 처리 정하기](https://github.com/hdmun/anything/issues/65)).
- `nvm`·`pnpm`·`go` 명령 자체의 설치: scoop·winget 항목이 한다.

## 변경 대상 파일

- `pc-setup/lib/AppRuntime.psm1` — 수정 (자리 → 구현)
- `pc-setup/tests/AppRuntime.Tests.ps1` — 신규
- `pc-setup/tests/Apps.Tests.ps1` — 수정 (테스트 17 '아직 구현되지 않은 원천 예외' 에서 nvm·pnpm·go 항목만 뺀다. 나머지 원천 항목과 단언은 그대로 둔다)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/AppRuntime.psm1
function Invoke-NvmApp  { param([Parameter(Mandatory)]$Entry, [bool]$Check) }   # → @{ Status; Detail }
function Invoke-PnpmApp { param([Parameter(Mandatory)]$Entry, [bool]$Check) }
function Invoke-GoApp   { param([Parameter(Mandatory)]$Entry, [bool]$Check) }

# 외부 명령 감싸기. 명령이 없으면 ExitCode = $null. 테스트는 Mock -ModuleName AppRuntime 으로 바꾼다.
function Invoke-Nvm  { param([Parameter(Mandatory)][string[]]$Arguments) }   # → @{ ExitCode; Output }
function Invoke-Pnpm { param([Parameter(Mandatory)][string[]]$Arguments) }
function Invoke-Go   { param([Parameter(Mandatory)][string[]]$Arguments) }

# 사용자 환경 변수 읽기·쓰기. 테스트는 Mock 한다.
function Get-UserEnv { param([Parameter(Mandatory)][string]$Name) }
function Set-UserEnv { param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Value) }

Export-ModuleMember -Function Invoke-NvmApp, Invoke-PnpmApp, Invoke-GoApp, Invoke-Nvm, Invoke-Pnpm, Invoke-Go, Get-UserEnv, Set-UserEnv
```

## 동작 명세

### 정상 경로

**`Invoke-NvmApp`** (`Entry.NodeLine` 예: `'26'`)

nvm v2 의 명령과 출력 모양은 이 PC 에 v2 가 없어 확인하지 못했다. 구현자는 nvm v2 공식 문서(저장소 `coreybutler/nvm-windows` 의 v2 문서와 릴리스 노트)에서 아래 네 가지 명령을 확인해 쓰고, 확인한 문서 링크를 테스트 파일 맨 위 주석에 적는다: (가) 버전 확인, (나) 설치된 Node 버전 목록, (다) 줄 하나 설치(`nvm install 26` 에 해당), (라) 기본 Node 확인과 지정. 출력 문구 대신 버전 문자열(`v?\d+\.\d+\.\d+`)만 뽑아 쓴다.

1. nvm 이 없거나 버전이 2 로 시작하지 않으면(v1 이 PATH 에 있는 경우 포함): `-Check` → `다름 (nvm v2 없음)`, 고치는 실행 → `실패: nvm v2 가 없다`.
2. 설치된 버전 가운데 `<NodeLine>.` 으로 시작하는 것이 있으면 `그대로`.
3. 없으면 `-Check` → `다름 (Node <NodeLine> 줄 없음)`. 고치는 실행 → 줄을 설치한다. 실패하면 `실패: nvm install <NodeLine> 종료 코드 <n>`.
4. 설치한 뒤 기본으로 쓰는 Node 가 없을 때만 그 줄을 기본으로 정한다. 이미 다른 기본 Node 가 있으면 바꾸지 않는다. `Update-SessionPath` 후 `바꿈`.

**`Invoke-PnpmApp`** (`Entry.Id` 예: `'@openai/codex'`)

1. **PNPM_HOME 맞춤**(`pnpm setup` 에 해당): 사용자 환경 변수 `PNPM_HOME` 이 비어 있으면 목표값은 `%LOCALAPPDATA%\pnpm`(펼친 경로), 있으면 그 값이다. 사용자 PATH 에 그 폴더가 없으면 넣어야 한다.
   - `-Check`: 환경 변수가 없으면 `다름 (PNPM_HOME 없음)`, PATH 에 없으면 `다름 (PNPM_HOME 이 PATH 에 없음)`.
   - 고치는 실행: 없으면 `Set-UserEnv PNPM_HOME <값>`, 현재 프로세스 `$env:PNPM_HOME` 도 맞춘다. PATH 는 `Add-UserPath <값>`(맨 뒤). 하나라도 바꿨으면 이 항목 결과는 최소 `바꿈` 이다.
2. `Update-SessionPath` 후 `pnpm` 이 없으면: `-Check` → `다름 (pnpm 없음)`, 고치는 실행 → `실패: pnpm 이 없다`.
3. `Invoke-Pnpm @('ls','-g','--json')` 출력을 JSON 으로 읽어 첫 원소의 `dependencies` 키 목록에 `Id` 가 있으면 설치됨이다. `dependencies` 가 없으면 빈 목록이다.
4. 설치됨이면 (1 에서 바꾼 것이 없을 때) `그대로`. 없음이면 `-Check` → `다름 (설치 안 됨)`, 고치는 실행 → `Invoke-Pnpm @('add','-g',<Id>)`. 0 이면 `바꿈`, 아니면 `실패: pnpm add -g <Id> 종료 코드 <n>`.

**`Invoke-GoApp`** (`Entry.Id` 예: `'golang.org/x/tools/gopls'`)

1. `Update-SessionPath` 후 `go` 가 없으면: `-Check` → `다름 (go 없음)`, 고치는 실행 → `실패: go 가 없다`.
2. `Invoke-Go @('env','GOPATH')` 의 첫 줄(여러 경로면 `;` 앞 첫 경로)에 `\bin\<Id 의 마지막 '/' 뒤 조각>.exe` 가 있으면 `그대로`.
3. 없으면 `-Check` → `다름 (설치 안 됨)`. 고치는 실행 → `Invoke-Go @('install',"<Id>@latest")`. 0 이면 `바꿈`, 아니면 `실패: go install <Id>@latest 종료 코드 <n>`.

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다(외부 명령 감싸기·`Get-UserEnv`·`Set-UserEnv`·`Update-SessionPath`·`Add-UserPath`·`Test-Path` 를 Mock). **열거하지 않은 경우는 범위 밖이다**(예: nvm v3, pnpm 전역 폴더가 둘, `GOBIN` 을 따로 정한 경우).

| # | 원천 | 상황 | `-Check` | 기대 |
|---|---|---|---|---|
| 1 | nvm | nvm 없음 | 예 / 아님 | 다름 (nvm v2 없음) / 실패: nvm v2 가 없다 |
| 2 | nvm | 버전 확인이 `1.2.2` | 예 | 다름 (nvm v2 없음) |
| 3 | nvm | 26.1.0 설치됨 | 둘 다 | 그대로 |
| 4 | nvm | 23.3.0 만 있음, 기본 23.3.0 | 아님 | 26 설치, 기본 안 바꿈, 바꿈 |
| 5 | nvm | 아무 버전도 없음 | 아님 | 26 설치 후 기본으로 지정, 바꿈 |
| 6 | nvm | 설치된 버전이 `v126.0.0` 하나 | 예 | 다름 (Node 26 줄 없음). 앞의 `v` 를 떼고 `26.` 으로 시작하는지 본다 |
| 7 | pnpm | PNPM_HOME 있음·PATH 있음·패키지 있음 | 둘 다 | 그대로 |
| 8 | pnpm | `dependencies` 없음 | 예 | 다름 (설치 안 됨) |
| 9 | pnpm | PNPM_HOME 없음 | 아님 | `Set-UserEnv PNPM_HOME %LOCALAPPDATA%\pnpm(펼침)` + `Add-UserPath` + add, 바꿈 |
| 10 | pnpm | PNPM_HOME 없음, 패키지는 있음 | 아님 | 환경만 맞추고 바꿈, add 안 불림 |
| 11 | pnpm | pnpm 없음 | 아님 | 실패: pnpm 이 없다 |
| 12 | pnpm | add 종료 코드 1 | 아님 | 실패 |
| 13 | go | exe 있음 | 둘 다 | 그대로 |
| 14 | go | exe 없음 | 예 / 아님 | 다름 (설치 안 됨) / `go install golang.org/x/tools/gopls@latest`, 바꿈 |
| 15 | go | go 없음 | 아님 | 실패: go 가 없다 |
| 16 | go | Id `honnef.co/go/tools/cmd/staticcheck` | 둘 다 | `staticcheck.exe` 를 본다 |
| 17 | 셋 다 | 명령을 찾기 전 | 둘 다 | `Update-SessionPath` 가 먼저 불림 |

### 에러 처리

- 예상하지 못한 예외는 잡지 않는다. 셋업 흐름이 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `pc-setup/lib/AppWinget.psm1`·`pc-setup/lib/AppScoop.psm1` — 같은 모양의 원천 모듈.
- `pc-setup/lib/EnvPath.psm1` — `Update-SessionPath`·`Add-UserPath`.
- `pc-setup/lib/Apps.psm1` — 세 함수를 부르는 자리.

## 인수 조건

- [ ] 엣지 케이스 표 1~17 이 각각 테스트로 있다.
- [ ] 테스트 파일 맨 위 주석에 nvm v2 명령을 확인한 공식 문서 링크가 있다.
- [ ] 테스트가 실제 nvm·pnpm·go 를 부르지 않고, 실제 사용자 환경 변수·PATH 를 쓰지 않는다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 `nvm install`·`pnpm add -g`·`go install` 을 돌리는 것, nvm v1 을 지우는 것.
- nvm v1 출력을 v2 처럼 해석해 `그대로` 를 내는 것.
- 버전을 고정하는 것(`@<버전>`), 업그레이드하는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
