> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/100
> updatedAt: 2026-11-15T08:58:31Z

# 공식 배포 WSL·Ubuntu 24.04 스크립트를 더한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. 앞 이슈 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)이 앱 단계(`pc-setup/lib/Apps.psm1` 의 `Get-AppItems`)를 만들었다. **원천**이 `official` 인 `apps.psd1` 항목은 `pc-setup/apps/<Id>.ps1` 이 있어야 하고, 셋업이 그 스크립트를 `Invoke-ItemScript` 로 부른다. `Elevated = $true` 면 **승격 단계**에서 부른다. 부모 이슈 [pc-setup 앱: 공식 배포 9개](https://github.com/hdmun/anything/issues/99)의 표가 이 이슈의 9개 항목이다.

이 태스크는 WSL 과 Ubuntu 24.04 를 맡는다([앱 목록 선별하기](https://github.com/hdmun/anything/issues/43) 「원천」, [앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44) 「재부팅·순서」).

- WSL: `wsl --install --no-distribution` 으로 설치한다. winget 의 WSL 은 7일 넘게 뒤처져 공식 배포를 쓴다. 관리자 권한이 필요하고, 처음 설치하면 재부팅해야 쓸 수 있다. 셋업은 스스로 재부팅하지 않고 `할 일: 재부팅 후 셋업 다시 실행` 을 낸다.
- Ubuntu 24.04: `wsl --install -d Ubuntu-24.04` 로 설치한다. `apps.psd1` 에서 `wsl` 바로 다음 줄이다. WSL 을 아직 쓸 수 없으면(재부팅 전) `할 일: 재부팅 후 셋업 다시 실행` 을 낸다.

이 PC 에서 확인한 사실(2026-11-11, 일반 권한):

- `Get-WindowsOptionalFeature -Online` 은 일반 권한에서 `COMException: 요청한 작업을 수행하려면 권한 상승이 필요합니다` 로 실패한다. `Get-CimInstance Win32_OptionalFeature` 는 일반 권한에서 읽힌다(`InstallState`: 1 켜짐, 2 꺼짐, 3 없음). 이 PC 는 `VirtualMachinePlatform`·`Microsoft-Windows-Subsystem-Linux` 가 1 이다.
- WSL 은 Store 패키지 `MicrosoftCorporationII.WindowsSubsystemForLinux` 3.0.5.0 이다(`Get-AppxPackage` 로 일반 권한에서 읽힘).
- `wsl -l -q` 는 UTF-16LE 로 출력해서 그대로 읽으면 글자 사이에 NUL 이 낀다. 환경 변수 `WSL_UTF8=1` 을 두고 부르면 UTF-8 로 나온다. 이 PC 의 배포판은 `Ubuntu-24.04`, `docker-desktop` 이다.
- 그래서 이 PC 의 `-Check` 기대 결과는 `wsl`·`ubuntu-24.04` 모두 `그대로` 다.

## 범위 밖 (건드리지 말 것)

- `pc-setup/lib/Apps.psm1`·`ItemScript.psm1`·`Setup.psm1` 의 동작. 버그를 찾으면 `ask` 로 묻는다.
- 다른 공식 배포 항목(다른 태스크).
- Ubuntu 안의 사용자 만들기·패키지 설치. 첫 실행은 사람이 한다.
- 이 PC 의 WSL·배포판을 바꾸는 실행(`wsl --install`·`--unregister` 등).

## 변경 대상 파일

- `pc-setup/apps/wsl.ps1` — 신규
- `pc-setup/apps/ubuntu-24.04.ps1` — 신규
- `pc-setup/apps.psd1` — 수정 (끝에 2줄 추가)
- `pc-setup/tests/OfficialWsl.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/apps/wsl.ps1, pc-setup/apps/ubuntu-24.04.ps1
[CmdletBinding()]
param([switch]$Check)
```

`apps.psd1` 끝에 이 순서로 더한다:

```powershell
@{ Id = 'wsl'; Origin = 'official'; Elevated = $true }
@{ Id = 'ubuntu-24.04'; Origin = 'official' }
```

## 동작 명세

### 정상 경로

**판정 표**

| 스크립트 | 「설치됨」 판정 | `-Check` | 고치는 실행 |
|---|---|---|---|
| `wsl` | `Get-AppxPackage MicrosoftCorporationII.WindowsSubsystemForLinux` 가 있고, `Win32_OptionalFeature` 의 `VirtualMachinePlatform` `InstallState` 가 1 | 맞으면 `그대로`, 아니면 `다름 (<무엇이 없나>)` | 패키지가 없으면 `wsl --install --no-distribution` 을 부른다. 끝나고 다시 읽어 판정이 맞으면 `바꿈`, 패키지는 있는데 기능이 아직 1 이 아니면 `할 일: 재부팅 후 셋업 다시 실행`. 패키지가 이미 있고 기능만 1 이 아니어도 `할 일: 재부팅 후 셋업 다시 실행`(설치 명령을 다시 부르지 않는다) |
| `ubuntu-24.04` | `WSL_UTF8=1` 로 부른 `wsl -l -q` 출력 줄 가운데 `Ubuntu-24.04` 가 있다(앞뒤 공백 제거, 정확히 같음) | 있으면 `그대로`, WSL 을 쓸 수 없으면 `할 일: 재부팅 후 셋업 다시 실행`, 아니면 `다름 (배포판 없음)` | 있으면 `그대로`. WSL 을 쓸 수 없으면(위 `wsl` 판정이 맞지 않음) `할 일: 재부팅 후 셋업 다시 실행`. 아니면 `wsl --install -d Ubuntu-24.04 --no-launch` 를 부르고, 다시 읽어 있으면 `할 일: wsl -d Ubuntu-24.04 로 처음 실행해 사용자를 만든다` |

- `ubuntu-24.04` 의 설치 결과를 `바꿈` 이 아니라 `할 일` 로 두는 이유: `--no-launch` 로 설치하면 첫 실행(사용자 만들기)이 남는다. 다음 셋업 실행에서는 배포판이 있으므로 `그대로` 다(멱등 판정에 걸리지 않는다).
- 외부 명령의 종료 코드가 0 이 아니면 `실패: <명령> 종료 코드 <n>`. 단 `wsl --install` 이 재부팅 필요를 뜻하는 코드로 끝나도 다시 읽은 상태로 판정한다(위 표). 종료 코드만 보고 `실패` 를 내지 않는다.
- `wsl` 이 `PATH` 에 없으면(아주 오래된 Windows) `실패: wsl.exe 없음`.
- 진행 설명은 `Write-Host`, 결과는 `Write-Output` 마지막 한 줄이다.

**시험할 수 있는 구조** (1번 구현 이슈의 `windows/*.ps1` 과 같은 방식)

- 상태 읽기(`Get-AppxPackage`, `Get-CimInstance`, `wsl -l -q`)와 쓰기(`wsl --install ...`)를 스크립트 안의 작은 함수로 나눈다(예: `Get-WslPackage`, `Get-FeatureState -Name`, `Get-WslDistros`, `Invoke-Wsl -Arguments`).
- 본문은 `Invoke-Main -Check:$Check` 함수다. 스크립트 맨 아래는 `if ($MyInvocation.InvocationName -ne '.') { Invoke-Main -Check:$Check }` 다. 테스트는 스크립트를 dot-source 해 함수를 얻고, 읽기·쓰기 함수를 `Mock` 한 뒤 `Invoke-Main` 을 부른다.
- 두 스크립트는 WSL 판정 함수를 각자 가진다(공용 파일을 만들지 않는다. `apps/` 의 `.ps1` 은 모두 항목 스크립트로 읽힌다).

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: WSL 1 만 있는 PC, inbox `wsl.exe` 만 있는 Windows 10).

| 스크립트 | 경우 | 기대 |
|---|---|---|
| wsl | 패키지 있음 + 기능 1 | 그대로 (쓰기 함수 안 불림) |
| wsl | 패키지 없음, `-Check` | `다름 (...)`, 쓰기 안 불림 |
| wsl | 패키지 없음 → 설치 뒤 패키지 있음 + 기능 2 | 설치 1번, `할 일: 재부팅 후 셋업 다시 실행` |
| wsl | 패키지 없음 → 설치 뒤 패키지 있음 + 기능 1 | `바꿈` |
| wsl | 패키지 있음 + 기능 2, 고치는 실행 | 설치 안 불림, `할 일: 재부팅 후 셋업 다시 실행` |
| wsl | 설치 명령 실패(종료 코드 1) 뒤 패키지 여전히 없음 | `실패: ...` |
| ubuntu | 배포판 목록에 `Ubuntu-24.04` | 그대로 |
| ubuntu | 목록에 `Ubuntu-22.04` 만 | `-Check` 는 `다름 (배포판 없음)`, 고치는 실행은 설치 1번 |
| ubuntu | WSL 쓸 수 없음 | 설치 안 불림, `할 일: 재부팅 후 셋업 다시 실행` |
| ubuntu | 설치 뒤 목록에 생김 | `할 일: wsl -d Ubuntu-24.04 로 처음 실행해 사용자를 만든다` |
| ubuntu | 목록 출력에 NUL 이 섞인 UTF-16 문자열이 와도(가짜 `wsl -l -q`) | `Get-WslDistros` 가 NUL 을 지우고 같은 결과 |

실제 선언: 저장소 `apps.psd1` 에 `wsl`(`Origin='official'`, `Elevated=$true`)이 있고 바로 다음 줄이 `ubuntu-24.04`(`Elevated` 없음)이며, 앱 선언 검사를 통과한다.

### 에러 처리

- 예상하지 못한 예외는 잡지 않아도 된다. `Invoke-ItemScript` 가 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `pc-setup/windows/Power.ps1`·`pc-setup/tests/WindowsScripts.Tests.ps1` — 항목 스크립트를 함수로 나누고 dot-source 로 시험하는 방식. 그대로 따른다.
- `pc-setup/lib/Apps.psm1` — `official` 항목 처리(`apps/<Id>.ps1` 존재 검사, `Elevated`).
- `pc-setup/lib/ItemScript.psm1` — 결과 줄 규칙.

## 인수 조건

- [ ] 엣지 케이스 표의 모든 행이 테스트로 있다.
- [ ] 테스트가 실제 `wsl --install` 을 부르지 않는다(쓰기 함수를 Mock).
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 `[앱] wsl: 그대로`, `[앱] ubuntu-24.04: 그대로` 를 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 스크립트를 `-Check` 없이 돌리는 것.
- 스크립트가 스스로 재부팅하는 것(`Restart-Computer`, `shutdown`).
- `-Check` 에서 `Get-WindowsOptionalFeature -Online` 을 쓰는 것(일반 권한에서 실패한다).
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
