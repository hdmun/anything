> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/87
> updatedAt: 2026-11-11T11:47:09Z

# Windows 설정 스크립트 3개(원격 데스크톱·최대 절전·전원)를 더한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 전체 설계는 부모 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다. 앞 태스크가 **Windows 설정** 단계(`lib/WindowsSettings.psm1`, `windows-settings.psd1` 레지스트리 값 8줄)를 만들었다. 그 단계는 `Script = $true` 줄을 `pc-setup/windows/<Id>.ps1` 항목 스크립트로 처리한다.

이 태스크는 레지스트리 값 하나로 쓸 수 없는 Windows 설정 3개를 항목 스크립트로 만든다([Windows 설정을 선언에 넣을지 정하기](https://github.com/hdmun/anything/issues/63) 「선언된 Windows 설정」).

| Id | 맞출 상태 | 승격 |
|---|---|---|
| `RemoteDesktop` | `HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server` `fDenyTSConnections` = 0, `HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp` `UserAuthentication` = 1(NLA), 방화벽 규칙 그룹 `@FirewallAPI.dll,-28752` 의 규칙이 모두 켜짐 | 예 |
| `Hibernate` | 최대 절전 끔. 읽기는 `HKLM:\SYSTEM\CurrentControlSet\Control\Power` `HibernateEnabled`(0 이 목표), 쓰기는 `powercfg /h off` | 예 |
| `Power` | 현재 활성 전원 구성표의 AC 절전 시간 0(안 함), AC 모니터 끄기 15분. 쓰기는 `powercfg /change standby-timeout-ac 0`, `powercfg /change monitor-timeout-ac 15` | 아니오 |

이 PC 에서 확인한 사실(같은 티켓 「검증」): `-Check` 에 필요한 값(HKLM 값·방화벽 규칙·`HibernateEnabled`)은 일반 권한으로 읽힌다. `powercfg /change` 는 일반 권한에서 동작한다. 방화벽 그룹 id `@FirewallAPI.dll,-28752` 는 Windows 표시 언어와 상관없다. 원격 데스크톱은 셋업이 켜고, rdp-notify 의 `install.ps1`(5번 구현 이슈)은 원격 데스크톱을 건드리지 않는다.

항목 스크립트 규칙(부모 이슈 「항목 스크립트 규칙」): `param([switch]$Check)` 하나, 상태를 먼저 보고 다를 때만 고침, 마지막 출력 줄 하나가 결과(`그대로`·`바꿈`·`할 일: …`·`실패: …`, `-Check` 는 `그대로`·`다름 (…)`·`확인 못 함: 관리자 필요`·`실패: …`).

## 범위 밖 (건드리지 말 것)

- 레지스트리 값 8줄과 `lib/WindowsSettings.psm1` 의 동작. 버그를 찾으면 `ask` 로 묻는다.
- 고성능 전원 구성표 선택, DC(배터리) 쪽 값, 원격 데스크톱 포트·사용자 그룹.
- rdp-notify.

## 변경 대상 파일

- `pc-setup/windows/RemoteDesktop.ps1` — 신규
- `pc-setup/windows/Hibernate.ps1` — 신규
- `pc-setup/windows/Power.ps1` — 신규
- `pc-setup/windows-settings.psd1` — 수정 (스크립트 3줄 추가)
- `pc-setup/tests/WindowsScripts.Tests.ps1` — 신규
- `pc-setup/tests/WindowsSettings.Tests.ps1` — 수정 (실제 선언 Id 목록 단언을 11개로)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/windows/<Id>.ps1 (세 파일 모두)
[CmdletBinding()]
param([switch]$Check)
```

선언에 넣는 줄(`LongPaths` 줄 바로 뒤, 이 순서):

```powershell
@{ Id = 'RemoteDesktop'; Script = $true; Elevated = $true }
@{ Id = 'Hibernate'; Script = $true; Elevated = $true }
@{ Id = 'Power'; Script = $true }
```

## 동작 명세

### 정상 경로

**`RemoteDesktop.ps1`**

1. 두 레지스트리 값과 방화벽 규칙(`Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752'`)을 읽는다. 규칙이 하나도 없으면 `실패: 원격 데스크톱 방화벽 규칙이 없다`.
2. 모두 맞으면 `그대로`.
3. `-Check` 면 다른 것들을 `다름 (<무엇>)` 으로 알린다. 예: `다름 (fDenyTSConnections 1, 방화벽 규칙 꺼짐 2개)`.
4. 고치는 실행이면 다른 값만 쓰고(`Set-ItemProperty`), 꺼진 규칙이 있으면 `Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'` 를 부른 뒤 `바꿈`.

**`Hibernate.ps1`**

1. `HibernateEnabled` 를 읽는다. 값이 0 이면 `그대로`. 값이 없으면 최대 절전이 꺼진 것으로 보고 `그대로`.
2. `-Check` 면 `다름 (HibernateEnabled <값>)`.
3. 고치는 실행이면 `powercfg /h off` 를 부른다. 종료 코드가 0 이 아니면 `실패: powercfg /h off 종료 코드 <n>`. 다시 읽어 0 이면 `바꿈`, 아니면 `실패: 최대 절전이 꺼지지 않았다`.

**`Power.ps1`**

1. `powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE` 와 `powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE` 출력에서 **현재 AC 값**을 읽는다. 출력 문구는 Windows 표시 언어에 따라 바뀌므로 문구에 기대지 않는다: 출력의 `0x[0-9a-fA-F]+` 값 가운데 **끝에서 두 번째** 가 AC, 마지막이 DC 다. 값은 초 단위다.
2. AC 절전 0 이고 AC 모니터 900(15분)이면 `그대로`.
3. `-Check` 면 `다름 (절전 <분>분, 모니터 <분>분)`(절전 0 은 `안 함`).
4. 고치는 실행이면 다른 값만 `powercfg /change standby-timeout-ac 0`·`powercfg /change monitor-timeout-ac 15` 로 바꾸고 `바꿈`. 종료 코드가 0 이 아니면 `실패: <명령> 종료 코드 <n>`.

공통

- 읽기에서 권한 오류(`UnauthorizedAccessException`·`SecurityException`·`Access is denied`)가 나면 `-Check` 는 `확인 못 함: 관리자 필요`, 고치는 실행은 `실패: 관리자 필요`.
- 진행 설명이 필요하면 `Write-Host` 로 쓴다. 결과 줄은 `Write-Output` 마지막 한 줄이다.
- 외부 명령(`powercfg`)과 레지스트리·방화벽 읽기·쓰기는 스크립트 안의 작은 함수로 감싸서 테스트가 `Mock` 할 수 있게 한다(예: `function Invoke-Powercfg { param([string[]]$Arguments) ... }`). 시험 방식은 아래 「엣지 케이스」 첫 단락을 따른다.
- 이 PC 의 `powercfg /query SCHEME_CURRENT SUB_VIDEO VIDEOIDLE` 출력(2026-11-11 확인)은 `가능한 최소 설정: 0x00000000` … `현재 AC 전원 설정 색인: 0x00000384`, `현재 DC 전원 설정 색인: 0x00000258` 로 끝난다. GUID 줄의 16진수에는 `0x` 가 붙지 않는다.

### 엣지 케이스

테스트 방식: 각 스크립트는 상태 읽기·쓰기를 스크립트 안의 함수로 나누고, 맨 아래에서 `if ($MyInvocation.InvocationName -ne '.') { <본문> }` 처럼 dot-source 될 때는 본문을 돌리지 않는다. 테스트는 스크립트를 dot-source 해 함수를 얻고, 읽기·쓰기 함수를 `Mock` 한 뒤 본문 함수(예: `Invoke-Main -Check:$Check`)를 부른다. 실제 레지스트리·방화벽·전원 설정을 바꾸지 않는다.

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 전원 구성표가 없는 PC, 방화벽 서비스 꺼짐).

| 스크립트 | 경우 | 기대 |
|---|---|---|
| RemoteDesktop | 모두 맞음 | 그대로 |
| RemoteDesktop | `fDenyTSConnections` 1, `-Check` | `다름 (...)`, 쓰기 함수 안 불림 |
| RemoteDesktop | 규칙 2개 꺼짐, 고치는 실행 | 방화벽 켜기 1번, 바꿈 |
| RemoteDesktop | 규칙 없음 | 실패 |
| RemoteDesktop | 읽기 권한 오류, `-Check` | 확인 못 함: 관리자 필요 |
| Hibernate | 0 / 값 없음 | 그대로 |
| Hibernate | 1, `-Check` | 다름 (HibernateEnabled 1) |
| Hibernate | 1, 고치는 실행, powercfg 성공 후 0 | 바꿈 |
| Hibernate | powercfg 종료 코드 1 | 실패 |
| Power | AC 0x0·0x384 | 그대로 |
| Power | 영어 출력과 한국어 출력 견본 각각에서 AC 값을 읽음 | 같은 값 |
| Power | 모니터 0x258(10분), `-Check` | `다름 (절전 안 함, 모니터 10분)` |
| Power | 절전만 다름, 고치는 실행 | standby 명령만 불림, 바꿈 |

`powercfg /query` 견본은 이 PC 의 실제 출력(한국어)을 테스트 파일에 문자열로 넣고, 영어 견본은 같은 모양의 영어 문구로 만든다.

실제 선언: 저장소 `windows-settings.psd1` 의 Id 11개가 `PowerShell51ExecutionPolicy, DeveloperMode, LongPaths, RemoteDesktop, Hibernate, Power, ShowFileExtensions, ShowHiddenFiles, DarkModeApps, DarkModeSystem, TaskbarSearchIcon` 순서이고, `Elevated` 는 `DeveloperMode`·`LongPaths`·`RemoteDesktop`·`Hibernate` 다(`WindowsSettings.Tests.ps1` 의 기존 단언을 고친다).

### 에러 처리

- 예상하지 못한 예외는 잡지 않아도 된다. `Invoke-ItemScript` 가 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `pc-setup/lib/WindowsSettings.psm1` — `Script` 줄 처리, `windows/<Id>.ps1` 존재 검사.
- `pc-setup/lib/ItemScript.psm1` — 결과 줄 읽기 규칙(마지막 문자열 줄).
- `pc-setup/tests/WindowsSettings.Tests.ps1` — 실제 선언 Id 단언(8개 → 11개로).

## 인수 조건

- [ ] 엣지 케이스 표의 모든 행이 테스트로 있다.
- [ ] 테스트가 실제 레지스트리·방화벽·전원 설정을 바꾸지 않는다.
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 Windows 설정 11줄을 출력하고 `실패` 0개로 끝난다(`RemoteDesktop`·`Hibernate`·`Power` 가 일반 권한으로 확인된다).
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 스크립트를 `-Check` 없이 돌리는 것.
- `powercfg` 출력의 한국어·영어 문구로 값을 찾는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
