> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/104
> updatedAt: 2026-11-19T10:56:00Z

# 공식 배포 Flutter·NVIDIA 드라이버 확인·Pester 스크립트를 더한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. **원천**이 `official` 인 `apps.psd1` 항목은 `pc-setup/apps/<Id>.ps1` 항목 스크립트로 처리된다. 앞 이슈 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)이 사용자 PATH 도우미 `pc-setup/lib/EnvPath.psm1`(`Update-SessionPath`, `Add-UserPath -Path <dir> [-Prepend]`, 바꿨으면 `$true`)을 만들었다. 부모 이슈 [pc-setup 앱: 공식 배포 9개](https://github.com/hdmun/anything/issues/99)의 표가 이 이슈의 9개 항목이다.

이 태스크는 남은 셋을 맡는다.

- `flutter`: Flutter SDK 를 공식 `git clone -b stable` 로 `~/develop/flutter` 에 받고, 사용자 PATH 에 `bin` 을 넣는다. 버전은 고정하지 않고, 올리기는 사람이 `flutter upgrade` 로 한다. fvm 은 쓰지 않는다([런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62) 「결론」). Android SDK 와 `flutter doctor --android-licenses` 는 수동 체크리스트(6번 구현 이슈)다.
- `nvidia-driver`: 설치하지 않고 확인만 한다. NVIDIA GPU 가 있는데 NVIDIA 드라이버가 없으면 `할 일: NVIDIA 드라이버 설치` 를 낸다([앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44) 「winget 밖 항목」).
- `pester`: 단위 테스트 도구. pwsh 7 에 기본으로 든 `Install-PSResource`(PSResourceGet)로 CurrentUser 에 설치한다([셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「단위 테스트」). 결정은 Pester 5 였지만 handoff 전 준비 때 사용자가 **Pester 6** 으로 바꿨다. 버전 줄은 6 이다.

확인한 사실(2026-11-11, 이 PC, 일반 권한):

- `~\develop\flutter\bin\flutter.bat` 이 있고 현재 브랜치는 `stable` 이다. 사용자 PATH 에 `C:\Users\<사용자>\develop\flutter\bin` 이 있다.
- 디스플레이 장치는 `NVIDIA GeForce RTX 5060 Ti`(하드웨어 ID `PCI\VEN_10DE&DEV_2D04...`)이고, `Win32_PnPSignedDriver` 의 `DriverProviderName` 은 `NVIDIA`, 드라이버 버전 32.0.16.1088 이다. 일반 권한에서 읽힌다.
- `Get-InstalledPSResource Pester -Scope CurrentUser` 는 6.2.0 을 돌려준다. Windows 기본 Pester 3.4.0 은 `C:\Program Files\WindowsPowerShell\Modules` 에 따로 있다.
- 그래서 이 PC 의 `-Check` 기대 결과는 세 항목 모두 `그대로` 다.

## 범위 밖 (건드리지 말 것)

- `pc-setup/lib/*.psm1` 의 동작. 버그를 찾으면 `ask` 로 묻는다.
- Android SDK, `flutter doctor`, Flutter 채널 바꾸기·업그레이드.
- NVIDIA 드라이버를 내려받거나 설치하는 것, NVIDIA App.
- Windows 기본 Pester 3.4.0 을 지우는 것, Pester 를 올리는 것.
- 다른 공식 배포 항목(다른 태스크).

## 변경 대상 파일

- `pc-setup/apps/flutter.ps1` — 신규
- `pc-setup/apps/nvidia-driver.ps1` — 신규
- `pc-setup/apps/pester.ps1` — 신규
- `pc-setup/apps.psd1` — 수정 (끝에 3줄 추가)
- `pc-setup/tests/AppsDeclaration.Tests.ps1` — 수정 (실제 선언 기대값만 이 태스크가 더한 줄에 맞춘다. 단언을 약하게 바꾸지 않는다: 앱 수 44→47, `expectedIds` 끝에 `'flutter'`·`'nvidia-driver'`·`'pester'`. Elevated 기대 목록과 수(19)는 그대로다. `It` 제목의 개수도 맞춘다: `...예외 없이 47개를 돌려준다`)
- `pc-setup/tests/OfficialMisc.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/apps/flutter.ps1, nvidia-driver.ps1, pester.ps1
[CmdletBinding()]
param([switch]$Check)
```

`apps.psd1` 끝에 이 순서로 더한다:

```powershell
@{ Id = 'flutter'; Origin = 'official' }
@{ Id = 'nvidia-driver'; Origin = 'official' }
@{ Id = 'pester'; Origin = 'official' }
```

## 동작 명세

### 정상 경로

**판정 표**

| 스크립트 | 「맞음」 판정 | `-Check` | 고치는 실행 |
|---|---|---|---|
| `flutter` | `~\develop\flutter\bin\flutter.bat` 이 있고, 사용자 PATH 에 `~\develop\flutter\bin` 이 있다(위치 무관) | 맞으면 `그대로`, 아니면 `다름 (<무엇>)` | 아래 「Flutter」 |
| `nvidia-driver` | 아래 「NVIDIA」 | 같은 판정(확인만) | 같은 판정(아무것도 바꾸지 않는다) |
| `pester` | `Get-InstalledPSResource Pester -Scope CurrentUser` 에 주 버전 6 이 있다 | 맞으면 `그대로`, 아니면 `다름 (Pester 6 없음)` | `Install-PSResource Pester -Version '[6.0,7.0)' -Scope CurrentUser -TrustRepository -Quiet` 후 다시 확인해 있으면 `바꿈`, 없으면 `실패: Pester 6 이 설치되지 않았다` |

**Flutter** (고치는 실행)

1. `Update-SessionPath` 를 부른다. 같은 셋업 실행의 승격 단계에서 막 설치된 Git 을 보게 하려는 것이다.
2. `~\develop\flutter` 가 없으면 `git clone -b stable https://github.com/flutter/flutter.git <경로>` 를 부른다(부모 폴더 `~\develop` 가 없으면 만든다). 종료 코드가 0 이 아니면 `실패: git clone 종료 코드 <n>`. `git` 을 찾지 못하면 `실패: git 없음`.
3. 폴더는 있는데 `bin\flutter.bat` 이 없으면 덮어쓰지 않고 `실패: ~/develop/flutter 가 Flutter 저장소가 아니다`.
4. 사용자 PATH 에 `bin` 이 없으면 `Add-UserPath -Path <bin>` 후 `Update-SessionPath`.
5. 무엇이든 바꿨으면 `바꿈`, 아니면 `그대로`.

- 브랜치·버전은 보지 않는다(고정 없음).
- `-Check` 의 `다름` 설명: `flutter.bat 없음`, `flutter\bin 이 사용자 PATH 에 없음`.

**NVIDIA**

1. `Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'"` 가운데 `HardWareID` 가 `PCI\VEN_10DE` 로 시작하는 장치를 찾는다. 드라이버가 없어서 기본 디스플레이 드라이버로 잡힌 장치도 하드웨어 ID 는 `VEN_10DE` 다.
2. 그런 장치가 없으면 → `그대로`(NVIDIA GPU 없음, VM 도 여기).
3. 하나라도 `DriverProviderName` 이 `NVIDIA` 가 아니면 → `할 일: NVIDIA 드라이버 설치`.
4. 모두 `NVIDIA` 면 → `그대로`.

- 고치는 실행과 `-Check` 가 같은 결과를 낸다. `할 일` 은 두 모드 모두 허용된 결과다.

**Pester**

- `Install-PSResource` 는 PSGallery 를 쓴다. 부트스트랩의 「PSGallery 없이」 규칙은 winget 보장에만 걸린다(이 항목은 셋업 안이다).
- 버전은 6 줄 안에서 고정하지 않는다. 이미 6.x 가 있으면 올리지 않는다.

공통

- 진행 설명은 `Write-Host`, 결과는 `Write-Output` 마지막 한 줄이다.
- 시험할 수 있는 구조: 읽기(파일 존재, 사용자 PATH, CIM, `Get-InstalledPSResource`)와 쓰기(`git clone`, `Add-UserPath`, `Update-SessionPath`, `Install-PSResource`)를 스크립트 안의 작은 함수로 나눈다. 본문은 `Invoke-Main -Check:$Check` 이고, 맨 아래 `if ($MyInvocation.InvocationName -ne '.') { Invoke-Main -Check:$Check }` 다. 테스트는 dot-source 후 그 함수들을 `Mock` 한다(1번 구현 이슈의 `windows/*.ps1` 과 같은 방식).
- 사용자 PATH 비교 규칙은 같은 이슈의 `apps/claude-code.ps1` 과 같다(레지스트리 값, 환경 변수 펼침, 끝 `\` 제거, 대소문자 무시).

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: GPU 여러 개 가운데 일부만 NVIDIA 드라이버, Flutter 폴더가 다른 위치, PSGallery 접속 실패의 재시도).

| 스크립트 | 경우 | 기대 |
|---|---|---|
| flutter | `flutter.bat` 있음 + PATH 있음 | 그대로, clone·PATH 쓰기 안 불림 |
| flutter | 폴더 없음, `-Check` | `다름 (flutter.bat 없음, ...)`, clone 안 불림 |
| flutter | 폴더 없음 → clone 성공, PATH 없음 | clone 1번(인자에 `-b stable`), `Add-UserPath` 1번, 바꿈 |
| flutter | clone 종료 코드 128 | `실패: git clone 종료 코드 128` |
| flutter | 폴더 있음 + `flutter.bat` 없음 | clone 안 불림, `실패: ...Flutter 저장소가 아니다` |
| flutter | `flutter.bat` 있음 + PATH 없음 | clone 안 불림, `Add-UserPath` 1번, 바꿈 |
| nvidia-driver | `VEN_10DE` 장치 없음 | 그대로 |
| nvidia-driver | `VEN_10DE` 장치 + 제공자 `NVIDIA`(이 PC 모양) | 그대로 |
| nvidia-driver | `VEN_10DE` 장치 + 제공자 `Microsoft` | `할 일: NVIDIA 드라이버 설치` (`-Check` 와 고치는 실행 모두) |
| pester | 6.2.0 있음 | 그대로, 설치 안 불림 |
| pester | 5.7.1 만 있음, `-Check` | `다름 (Pester 6 없음)` |
| pester | 없음 → 설치 → 6.2.0 생김 | 설치 1번(인자에 `-Version '[6.0,7.0)'`·`-Scope CurrentUser`), 바꿈 |
| pester | 설치 뒤에도 없음 | `실패: Pester 6 이 설치되지 않았다` |

실제 선언: 저장소 `apps.psd1` 에 세 줄이 `Origin='official'`, `Elevated` 없이 있고 앱 선언 검사를 통과한다.

### 에러 처리

- 예상하지 못한 예외는 잡지 않아도 된다. `Invoke-ItemScript` 가 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `pc-setup/lib/EnvPath.psm1` — `Update-SessionPath`·`Add-UserPath`.
- `pc-setup/apps/claude-code.ps1` — 같은 이슈 앞 태스크. 사용자 PATH 읽기·비교 함수 모양을 맞춘다(복사해도 된다. 공용 파일은 만들지 않는다).
- `pc-setup/windows/Power.ps1`·`pc-setup/tests/WindowsScripts.Tests.ps1` — 항목 스크립트를 함수로 나누고 dot-source 로 시험하는 방식.

## 인수 조건

- [ ] 엣지 케이스 표의 모든 행이 테스트로 있다.
- [ ] 테스트가 실제 `git clone`·`Install-PSResource`·사용자 PATH 쓰기를 하지 않는다.
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 `[앱] flutter: 그대로`, `[앱] nvidia-driver: 그대로`, `[앱] pester: 그대로` 를 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 스크립트를 `-Check` 없이 돌리는 것.
- Flutter 버전·채널을 고정하거나 `flutter upgrade` 를 부르는 것.
- NVIDIA 드라이버를 설치하려는 것.
- Pester 5 줄을 설치하는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
