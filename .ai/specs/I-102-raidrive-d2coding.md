> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/102
> updatedAt: 2026-11-19T10:55:57Z

# 공식 배포 RaiDrive·D2Coding 스크립트를 더한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. **원천**이 `official` 인 `apps.psd1` 항목은 `pc-setup/apps/<Id>.ps1` 항목 스크립트로 처리되고, `Elevated = $true` 면 **승격 단계**에서 불린다. 부모 이슈 [pc-setup 앱: 공식 배포 9개](https://github.com/hdmun/anything/issues/99)의 표가 이 이슈의 9개 항목이다.

이 태스크는 내려받아 설치하는 앱 둘을 맡는다.

- `raidrive`: winget 의 RaiDrive 가 7일 넘게 뒤처져(매니페스트 2024-11) 공식 설치 파일을 쓴다([앱 목록 선별하기](https://github.com/hdmun/anything/issues/43) 「원천」). 설치에 관리자 권한이 필요하다(공식 설치 문서: "Installation needs an administrator account").
- `d2coding`: winget 에 없고 scoop nerd-fonts 에는 이름이 다른 패치판만 있어서, GitHub 릴리스를 받아 **사용자 폰트**로 설치한다([앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44) 「winget 밖 항목」). 관리자 권한이 필요 없다.
- 멱등 기준은 설치 여부만이다. 이미 설치돼 있으면 버전이 낮아도 `그대로` 다(같은 티켓 「형식」).

확인한 사실(2026-11-11):

- RaiDrive 공식 내려받기 페이지 `https://www.raidrive.com/download` 의 최신판은 「RaiDrive Mount GUI」 2026.10.0 이고, x64 MSI 주소는 `https://app.raidrive.com/download/raidrive.mount/release/RaiDrive.Mount_2026.10.0_x64.msi` 다. 주소에 버전이 들어 있고 「최신」 고정 주소는 페이지에 없다. 페이지에 조용한 설치 옵션 설명은 없다.
- 이 PC 의 RaiDrive 는 제거 목록(HKLM `...\Uninstall\{7C6B280C-CD15-4CCF-9FBF-B7AC85D27630}`)에 DisplayName `RaiDrive Mount`, 버전 2026.6.25, 위치 `C:\Program Files\OpenBoxLab\RaiDrive Mount\` 로 있다. winget `OpenBoxLab.RaiDrive` 는 이 설치를 알아보지 못한다.
- D2Coding 저장소는 `naver/d2codingfont` 에서 `naver/d2-coding-font` 로 이름이 바뀌었다(GitHub API 가 옛 이름을 새 이름으로 넘겨 준다). 최신 릴리스는 `VER1.4.0`(2026-10-03), 자산은 zip 하나 `D2Coding-Ver1.4.0-20261003.zip` 이다. zip 안에는 `D2Coding/`·`D2CodingAll/`·`D2CodingLigature/` 폴더가 있고, `D2CodingAll/D2Coding-Ver1.4.0-20261003-all.ttc` 가 일반·굵게·합자를 모두 담은 파일이다.
- 이 PC 의 D2Coding 은 `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts` 에 값 이름 `D2Coding & D2Coding Bold & D2Coding ligature & D2Coding ligature Bold (TrueType)`, 값 `%LOCALAPPDATA%\Microsoft\Windows\Fonts\D2Coding-Ver1.3.2-20180524-all.ttc`(파일 있음)로 설치돼 있다.
- 그래서 이 PC 의 `-Check` 기대 결과는 `raidrive`·`d2coding` 모두 `그대로` 다.

## 범위 밖 (건드리지 말 것)

- `pc-setup/lib/*.psm1` 의 동작. 버그를 찾으면 `ask` 로 묻는다.
- 다른 공식 배포 항목(다른 태스크).
- RaiDrive 드라이브 연결 설정·로그인, 폰트를 터미널·편집기 설정에 거는 일(설정 파일은 5번 구현 이슈).
- 이미 설치된 앱·폰트를 올리거나 지우는 것.

## 변경 대상 파일

- `pc-setup/apps/raidrive.ps1` — 신규
- `pc-setup/apps/d2coding.ps1` — 신규
- `pc-setup/apps.psd1` — 수정 (끝에 2줄 추가)
- `pc-setup/tests/AppsDeclaration.Tests.ps1` — 수정 (실제 선언 기대값만 이 태스크가 더한 줄에 맞춘다. 단언을 약하게 바꾸지 않는다: 앱 수 40→42, `expectedIds` 끝에 `'raidrive'`·`'d2coding'`, Elevated 기대 목록 끝(`'wsl'` 다음)에 `'raidrive'`, Elevated 수 18→19. `It` 제목의 개수도 맞춘다: `...예외 없이 42개를 돌려준다`, `Elevated 인 항목이 정확히 기대 목록 19개다`)
- `pc-setup/tests/OfficialDownloads.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/apps/raidrive.ps1, pc-setup/apps/d2coding.ps1
[CmdletBinding()]
param([switch]$Check)
```

`apps.psd1` 끝에 이 순서로 더한다:

```powershell
@{ Id = 'raidrive'; Origin = 'official'; Elevated = $true }
@{ Id = 'd2coding'; Origin = 'official' }
```

## 동작 명세

### 정상 경로

**판정 표**

| 스크립트 | 「설치됨」 판정 | `-Check` | 고치는 실행 |
|---|---|---|---|
| `raidrive` | HKLM 제거 목록(`SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*` 와 `SOFTWARE\WOW6432Node\...\Uninstall\*`)에 `DisplayName` 이 `RaiDrive` 로 시작하는 항목이 있다 | 있으면 `그대로`, 없으면 `다름 (설치 안 됨)` | 아래 「RaiDrive 설치」 |
| `d2coding` | HKCU 폰트 목록(`HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts`)에 이름이 `D2Coding` 으로 시작하는 값이 있고, 그 값이 가리키는 파일이 있다(버전은 보지 않는다) | 있으면 `그대로`, 없으면 `다름 (설치 안 됨)` | 아래 「D2Coding 설치」 |

**RaiDrive 설치** (승격 단계에서 불린다)

1. `https://www.raidrive.com/download` 페이지를 받아, `href` 가운데 정규식 `https://app\.raidrive\.com/download/raidrive\.mount/release/RaiDrive\.Mount_[0-9.]+_x64\.msi` 에 맞는 첫 주소를 찾는다. 없으면 `실패: RaiDrive 내려받기 주소를 찾지 못했다`.
2. MSI 를 `$env:TEMP` 아래 새 폴더에 받는다.
3. `msiexec.exe /i <msi> /qn /norestart` 를 부르고 끝날 때까지 기다린다. 종료 코드 0 → 다시 판정해 설치됐으면 `바꿈`. 3010 → `할 일: 재부팅 후 셋업 다시 실행`. 그 밖 → `실패: msiexec 종료 코드 <n>`.
4. 받은 파일과 폴더를 지운다.

- 구현 전에 공식 설치 문서(`https://docs.raidrive.com/en/gui/gettingstarted/install/`)와 내려받기 페이지를 다시 읽어, 위 주소 모양과 MSI 조용한 설치가 맞는지 확인한다. 다르면 `ask` 로 묻는다.

**D2Coding 설치** (일반 권한)

1. `https://api.github.com/repos/naver/d2-coding-font/releases/latest` 를 읽고, 자산 가운데 이름이 `D2Coding-Ver*.zip` 인 첫 자산을 받는다. 없으면 `실패: D2Coding 릴리스 자산을 찾지 못했다`.
2. `$env:TEMP` 아래 새 폴더에 풀고, `D2CodingAll/` 아래 `*-all.ttc` 하나를 찾는다. 없으면 `실패: D2Coding all.ttc 가 없다`.
3. 그 파일을 `%LOCALAPPDATA%\Microsoft\Windows\Fonts\` 로 복사한다(폴더가 없으면 만든다).
4. HKCU 폰트 목록에 값 이름 `D2Coding & D2Coding Bold & D2Coding ligature & D2Coding ligature Bold (TrueType)`, 값 = 복사한 파일의 전체 경로(String)를 쓴다.
5. 받은 파일과 폴더를 지우고 `바꿈`. 이미 열린 앱은 다시 시작해야 새 폰트를 본다. 이것은 `할 일` 로 만들지 않는다.

공통

- 내려받기는 `Invoke-WebRequest` 로 한다. GitHub API 는 인증 없이 부른다.
- 진행 설명은 `Write-Host`, 결과는 `Write-Output` 마지막 한 줄이다.

**시험할 수 있는 구조** (1번 구현 이슈의 `windows/*.ps1` 과 같은 방식)

- 읽기(제거 목록·폰트 목록·파일 존재), 내려받기(페이지·API·파일), 쓰기(`msiexec`, 복사, 레지스트리 쓰기)를 스크립트 안의 작은 함수로 나눈다.
- 본문은 `Invoke-Main -Check:$Check` 이고, 맨 아래 `if ($MyInvocation.InvocationName -ne '.') { Invoke-Main -Check:$Check }` 다. 테스트는 dot-source 후 그 함수들을 `Mock` 한다. 실제 내려받기·설치·레지스트리 쓰기를 하지 않는다.

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: ARM64 PC, 프록시, GitHub API 요청 한도 초과의 재시도).

| 스크립트 | 경우 | 기대 |
|---|---|---|
| raidrive | 제거 목록에 `RaiDrive Mount` | 그대로, 내려받기 안 불림 |
| raidrive | 없음, `-Check` | `다름 (설치 안 됨)`, 내려받기 안 불림 |
| raidrive | 없음 → 페이지에 MSI 주소 → msiexec 0 → 다시 읽으면 있음 | `바꿈`, msiexec 인자에 `/qn`·`/norestart` |
| raidrive | msiexec 3010 | `할 일: 재부팅 후 셋업 다시 실행` |
| raidrive | msiexec 1603 | `실패: msiexec 종료 코드 1603` |
| raidrive | 페이지에 맞는 주소 없음 | `실패: RaiDrive 내려받기 주소를 찾지 못했다` |
| d2coding | 폰트 값 있음 + 파일 있음 | 그대로 |
| d2coding | 폰트 값 있음 + 파일 없음, `-Check` | `다름 (설치 안 됨)` |
| d2coding | 없음 → 자산 받기 → `D2CodingAll/*-all.ttc` 있음 | 복사 1번, 레지스트리 쓰기 1번(위 값 이름), `바꿈` |
| d2coding | 릴리스에 zip 자산 없음 | `실패: D2Coding 릴리스 자산을 찾지 못했다` |
| d2coding | zip 안에 `D2CodingAll` 없음 | `실패: D2Coding all.ttc 가 없다` |

zip 풀기 경우는 `TestDrive:` 에 위 「확인한 사실」의 폴더 구조를 흉내 낸 작은 zip 을 만들어 시험한다.

실제 선언: 저장소 `apps.psd1` 에 `raidrive`(`Elevated=$true`)·`d2coding`(`Elevated` 없음)이 `Origin='official'` 로 있고 앱 선언 검사를 통과한다.

### 에러 처리

- 내려받기 예외는 `실패: <예외 메시지>` 로 끝내도 되고, 잡지 않아도 된다(`Invoke-ItemScript` 가 `실패` 로 바꾼다).

## 기존 코드 참조

- `pc-setup/windows/RemoteDesktop.ps1`·`pc-setup/tests/WindowsScripts.Tests.ps1` — 항목 스크립트를 함수로 나누고 dot-source 로 시험하는 방식.
- `pc-setup/lib/Apps.psm1` — `official` 항목 처리.

## 인수 조건

- [ ] 엣지 케이스 표의 모든 행이 테스트로 있다.
- [ ] 테스트가 네트워크에 나가지 않고, 실제 msiexec·폰트 폴더·`HKCU` 폰트 목록을 건드리지 않는다.
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 `[앱] raidrive: 그대로`, `[앱] d2coding: 그대로` 를 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 스크립트를 `-Check` 없이 돌리는 것.
- winget `OpenBoxLab.RaiDrive` 나 scoop nerd-fonts 로 바꾸는 것.
- 버전을 비교해 올리는 것(설치 여부만 본다).
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
