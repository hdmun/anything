> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/103
> updatedAt: 2026-11-19T21:40:54Z

# 공식 배포 agy·Claude Code 스크립트를 더한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. **원천**이 `official` 인 `apps.psd1` 항목은 `pc-setup/apps/<Id>.ps1` 항목 스크립트로 처리된다. 앞 이슈 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)이 사용자 PATH 도우미 `pc-setup/lib/EnvPath.psm1`(`Update-SessionPath`, `Add-UserPath -Path <dir> [-Prepend]`, 바꿨으면 `$true`)을 만들었다. 부모 이슈 [pc-setup 앱: 공식 배포 9개](https://github.com/hdmun/anything/issues/99)의 표가 이 이슈의 9개 항목이다.

이 태스크는 공식 설치 스크립트로 설치하고 스스로 업데이트하는 에이전트 CLI 둘을 맡는다.

- `agy`: 설치 명령은 공식 문서에서 확인한다고 정했다([앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44) 「winget 밖 항목」).
- `claude-code`: 공식 설치 스크립트를 `latest` 채널로 실행한다. 설치 스크립트는 PATH 를 바꾸지 않으므로 셋업이 `~/.local/bin` 을 사용자 PATH **맨 앞**에 넣는다. 맨 앞인 이유는 옛 npm 판(`%APPDATA%\npm`)이 남은 PC 에서 새 판이 먼저 실행되게 하려는 것이다([런타임 전역 패키지 선언 정하기](https://github.com/hdmun/anything/issues/67) 「claude-code: 공식 배포」). 사람이 손으로 설치한 Claude Code 는 셋업에서 설치된 것으로 보이고, PATH 맞춤만 `바꿈` 으로 나올 수 있다([집의 다른 PC 로 셋업을 검증하는 방식 정하기](https://github.com/hdmun/anything/issues/71) 「셋업 전 정리」).
- 멱등 기준은 설치 여부만이다. 두 CLI 모두 스스로 업데이트하므로 버전은 보지 않는다.

확인한 사실(2026-11-11):

- agy 공식 Windows 설치 스크립트 `https://antigravity.google/cli/install.ps1` 은 매니페스트에서 바이너리를 받아 SHA-512 를 확인한 뒤 `%LOCALAPPDATA%\agy\bin\agy.exe` 에 둔다. 사용자 PATH 를 직접 바꾸지 않고, 마지막에 `agy.exe install` 을 부른다(오류는 무시). `agy.exe` 가 이미 있으면 다시 설치하지 않고 종료 코드 0 으로 끝난다. 일부 2차 자료는 `antigravity.google/install.ps1`(`/cli/` 없음)을 적지만, 위 주소가 실제로 받아진다.
- Claude Code 공식 문서(`https://code.claude.com/docs/en/setup`): Windows PowerShell 설치 명령은 `irm https://claude.ai/install.ps1 | iex` 이고 기본 채널이 `latest` 다. 관리자 권한이 필요 없다. Git for Windows 는 **필요하지 않다**(있으면 Bash 도구에 쓰고, 없으면 PowerShell 도구를 쓴다). 설치 위치는 `%USERPROFILE%\.local\bin\claude.exe` 다. 설치 뒤 `claude` 를 찾지 못하면 PATH 를 고치라고 안내한다.
- 이 PC: `%LOCALAPPDATA%\agy\bin\agy.EXE` 가 있고 사용자 PATH 에 `C:\Users\<사용자>\AppData\Local\agy\bin` 이 있다. `%USERPROFILE%\.local\bin\claude.exe` 는 없고(npm 판만 있음), 사용자 PATH 에 `~/.local/bin` 도 없다. 그래서 이 PC 의 `-Check` 기대 결과는 `agy` 는 `그대로`, `claude-code` 는 `다름 (claude.exe 없음, ~/.local/bin 이 사용자 PATH 맨 앞이 아님)` 이다(`다름` 은 게이트에서 허용).

## 범위 밖 (건드리지 말 것)

- `pc-setup/lib/*.psm1` 의 동작. 단 `EnvPath.psm1` 의 `Add-UserPath` 하나는 아래 「`Add-UserPath` 바꾸기」대로 고친다. 그 모듈의 다른 함수와 다른 모듈은 건드리지 않는다.
- **에이전트 폴더**(`~/.claude`·`~/.gemini`·agy 설정 폴더 등)와 로그인([에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64)).
- npm 전역의 옛 claude-code·codex 를 지우는 것.
- 다른 공식 배포 항목(다른 태스크).

## 변경 대상 파일

- `pc-setup/apps/agy.ps1` — 신규
- `pc-setup/apps/claude-code.ps1` — 신규
- `pc-setup/apps.psd1` — 수정 (끝에 2줄 추가)
- `pc-setup/lib/EnvPath.psm1` — 수정 (`Add-UserPath` 만)
- `pc-setup/tests/AppsDeclaration.Tests.ps1` — 수정 (실제 선언 기대값만 이 태스크가 더한 줄에 맞춘다. 단언을 약하게 바꾸지 않는다: 앱 수 42→44, `expectedIds` 끝에 `'agy'`·`'claude-code'`. Elevated 기대 목록과 수(19)는 그대로다. `It` 제목의 개수도 맞춘다: `...예외 없이 44개를 돌려준다`)
- `pc-setup/tests/EnvPath.Tests.ps1` — 수정 (엣지 케이스 표의 `Add-UserPath` 행을 더한다. 기존 테스트는 고치지 않고 그대로 통과해야 한다)
- `pc-setup/tests/OfficialAgentCli.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/apps/agy.ps1, pc-setup/apps/claude-code.ps1
[CmdletBinding()]
param([switch]$Check)
```

`apps.psd1` 끝에 이 순서로 더한다:

```powershell
@{ Id = 'agy'; Origin = 'official' }
@{ Id = 'claude-code'; Origin = 'official' }
```

`Add-UserPath` 는 시그니처를 그대로 두고 동작만 바꾼다:

```powershell
# pc-setup/lib/EnvPath.psm1
function Add-UserPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [switch]$Prepend
    )
    # 사용자 PATH 를 바꿨으면 $true, 바꾸지 않았으면 $false
}
```

## 동작 명세

### 정상 경로

두 스크립트는 `Import-Module (Join-Path $PSScriptRoot '..' 'lib' 'EnvPath.psm1')` 로 PATH 도우미를 쓴다. 사용자 PATH 는 레지스트리(`HKCU:\Environment` 의 `Path`)의 값으로 판단하고, 비교할 때 각 항목의 환경 변수를 펼치고 끝의 `\` 를 떼고 대소문자를 무시한다.

**판정 표**

| 스크립트 | 「설치됨」 판정 | PATH 조건 | `-Check` | 고치는 실행 |
|---|---|---|---|---|
| `agy` | `%LOCALAPPDATA%\agy\bin\agy.exe` 가 있다 | 사용자 PATH 에 `%LOCALAPPDATA%\agy\bin` 이 있다(위치 무관) | 둘 다 맞으면 `그대로`, 아니면 `다름 (<무엇>)` | 실행 파일이 없으면 설치 명령을 부르고 다시 확인한다(없으면 `실패: agy.exe 가 생기지 않았다`). PATH 에 없으면 `Add-UserPath -Path <dir>`. 무엇이든 바꿨으면 `바꿈`, 아니면 `그대로` |
| `claude-code` | `%USERPROFILE%\.local\bin\claude.exe` 가 있다 | 사용자 PATH 의 **첫 항목**이 `%USERPROFILE%\.local\bin` 이다 | 둘 다 맞으면 `그대로`, 아니면 `다름 (<무엇>)` | 실행 파일이 없으면 설치 명령을 부르고 다시 확인한다(없으면 `실패: claude.exe 가 생기지 않았다`). PATH 첫 항목이 아니면 `Add-UserPath -Path <dir> -Prepend`. 무엇이든 바꿨으면 `바꿈`, 아니면 `그대로` |

`다름` 의 설명 문구: `agy.exe 없음`, `agy\bin 이 사용자 PATH 에 없음`, `claude.exe 없음`, `~/.local/bin 이 사용자 PATH 맨 앞이 아님`. 둘 다 해당하면 `, ` 로 잇는다.

**설치 명령**

- 같은 프로세스에서 `iex` 하지 않는다(설치 스크립트가 `exit` 하면 셋업이 끝난다). 자식 프로세스로 부른다: `pwsh -NoProfile -Command "irm <주소> | iex"`. 주소는 agy `https://antigravity.google/cli/install.ps1`, claude-code `https://claude.ai/install.ps1`.
- 자식의 종료 코드가 0 이 아니면 `실패: 설치 스크립트 종료 코드 <n>`.
- 설치 뒤 `Update-SessionPath` 를 불러 같은 셋업 실행의 다음 항목이 새 PATH 를 보게 한다. PATH 를 바꾼 뒤에도 부른다.

**`Add-UserPath` 바꾸기** (`pc-setup/lib/EnvPath.psm1`)

지금은 경로가 이미 있으면 `-Prepend` 여도 순서를 바꾸지 않고 `$false` 를 돌려준다. 그래서 손으로 설치해 `~/.local/bin` 이 PATH 중간에 있는 PC 에서는 순서가 바뀌지 않고 `-Check` 가 계속 `다름` 을 낸다. 아래처럼 바꾼다.

- 비교: 각 항목과 `$Path` 의 환경 변수를 펼치고(`[Environment]::ExpandEnvironmentVariables`), 끝의 `\` 를 떼고, 대소문자를 무시한다.
- `-Prepend` 없음: 같은 항목이 있으면 아무것도 쓰지 않고 `$false`. 없으면 맨 뒤에 `$Path` 를 넣고 `$true`. 비교에 환경 변수 펼치기가 더해진 것 말고는 지금과 같다.
- `-Prepend`: 첫 항목이 같으면 아무것도 쓰지 않고 `$false`. 같은 항목이 다른 자리에 있으면 그 항목을 모두 빼고, 처음 찾은 항목을 **원래 꼴 그대로**(예: `%USERPROFILE%\.local\bin`) 맨 앞에 넣고 `$true`. 없으면 `$Path` 를 맨 앞에 넣고 `$true`. 나머지 항목의 순서는 그대로 둔다.
- 바꿨을 때만 `Set-UserPathEntries` 와 `Update-SessionPath` 를 부른다.
- pnpm 처리(`pc-setup/lib/AppRuntime.psm1:182`)는 `-Prepend` 없이 부른다. 그 호출은 위 규칙대로 펼친 꼴의 중복도 찾게 되는 것 말고는 바뀌지 않는다. `AppRuntime.psm1` 은 고치지 않는다.

**시험할 수 있는 구조** (1번 구현 이슈의 `windows/*.ps1` 과 같은 방식)

- 읽기(실행 파일 존재, 사용자 PATH 읽기), 쓰기(설치 명령 실행, `Add-UserPath`, `Update-SessionPath`)를 스크립트 안의 작은 함수로 나눈다.
- 본문은 `Invoke-Main -Check:$Check` 이고, 맨 아래 `if ($MyInvocation.InvocationName -ne '.') { Invoke-Main -Check:$Check }` 다. 테스트는 dot-source 후 그 함수들을 `Mock` 한다. 실제 설치 명령·사용자 PATH 쓰기를 하지 않는다.

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 사용자 PATH 가 비어 있음, `REG_SZ`/`REG_EXPAND_SZ` 종류 보존 검증, npm 판 claude 를 찾아 알리기).

| 스크립트 | 경우 | 기대 |
|---|---|---|
| agy | 실행 파일 있음 + PATH 에 있음(이 PC 모양) | 그대로, 설치·PATH 쓰기 안 불림 |
| agy | 실행 파일 없음, `-Check` | `다름 (agy.exe 없음, ...)`, 설치 안 불림 |
| agy | 실행 파일 없음 → 설치 → 생김, PATH 에 없음 | 설치 1번, `Add-UserPath` 1번, 바꿈 |
| agy | 설치 뒤에도 실행 파일 없음 | `실패: agy.exe 가 생기지 않았다` |
| agy | PATH 항목이 `%LOCALAPPDATA%\agy\bin\`(펼치지 않은 꼴, 끝 `\`) | PATH 조건 맞음 |
| claude-code | 실행 파일 있음 + PATH 첫 항목 | 그대로 |
| claude-code | 실행 파일 없음 + PATH 에 없음(이 PC 모양), `-Check` | `다름 (claude.exe 없음, ~/.local/bin 이 사용자 PATH 맨 앞이 아님)` |
| claude-code | 실행 파일 있음 + PATH 셋째 항목(손으로 설치한 경우) | 설치 안 불림, `Add-UserPath -Prepend` 1번, 바꿈 |
| claude-code | 실행 파일 없음 → 설치 → 생김 + PATH 없음 | 설치 1번, `-Prepend` 1번, 바꿈 |
| claude-code | 설치 자식 종료 코드 1 | `실패: 설치 스크립트 종료 코드 1` |
| `Add-UserPath` | `-Prepend`, 같은 경로가 셋째 항목 | 그 항목이 맨 앞으로 옮겨지고 나머지 순서는 그대로, 중복 없음, `$true` |
| `Add-UserPath` | `-Prepend`, 이미 첫 항목(대소문자·끝 `\` 다름) | `$false`, `Set-UserPathEntries`·`Update-SessionPath` 안 불림 |
| `Add-UserPath` | `-Prepend`, 둘째 항목이 `%USERPROFILE%\.local\bin`(펼치지 않은 꼴)이고 `$Path` 는 펼친 값 | `%USERPROFILE%\.local\bin` 꼴 그대로 맨 앞, `$true` |
| `Add-UserPath` | `-Prepend`, 같은 경로가 둘째·넷째에 두 번 | 둘 다 빠지고 하나만 맨 앞, `$true` |
| `Add-UserPath` | `-Prepend` 없음, `%LOCALAPPDATA%\pnpm` 꼴로 이미 있고 `$Path` 는 펼친 값 | `$false`, `Set-UserPathEntries` 안 불림 |

실제 선언: 저장소 `apps.psd1` 에 `agy`·`claude-code` 가 `Origin='official'`, `Elevated` 없이 있고 앱 선언 검사를 통과한다.

### 에러 처리

- 예상하지 못한 예외는 잡지 않아도 된다. `Invoke-ItemScript` 가 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `pc-setup/lib/EnvPath.psm1` — `Update-SessionPath`·`Add-UserPath`(이 태스크가 고친다)·`Get-UserPathEntries`·`Set-UserPathEntries`. 3번 구현 이슈의 nvm·pnpm·go 처리가 쓰는 방식을 따른다.
- `pc-setup/tests/EnvPath.Tests.ps1` — 기존 `Add-UserPath` 테스트 모양(`Get-UserPathEntries`·`Set-UserPathEntries` 를 `Mock -ModuleName EnvPath`).
- `pc-setup/lib/AppRuntime.psm1:182` — `-Prepend` 없이 부르는 pnpm 처리.
- `pc-setup/windows/Power.ps1`·`pc-setup/tests/WindowsScripts.Tests.ps1` — 항목 스크립트를 함수로 나누고 dot-source 로 시험하는 방식.

## 인수 조건

- [ ] 엣지 케이스 표의 모든 행이 테스트로 있다.
- [ ] 테스트가 네트워크에 나가지 않고, 실제 사용자 PATH 를 바꾸지 않는다.
- [ ] 기존 `EnvPath.Tests.ps1`·`AppRuntime.Tests.ps1` 의 테스트를 고치지 않고 그대로 통과한다.
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 `[앱] agy: 그대로` 와 `[앱] claude-code: 다름 (...)` 를 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 스크립트를 `-Check` 없이 돌리는 것(이 PC 의 PATH 순서가 바뀐다).
- 설치 스크립트를 셋업 프로세스 안에서 `iex` 하는 것.
- winget `Anthropic.ClaudeCode`·npm·pnpm 으로 claude-code 를 설치하는 것, `stable` 채널을 쓰는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
