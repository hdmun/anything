> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/95
> updatedAt: 2026-11-15T08:58:26Z

# winget 원천으로 앱을 확인하고 설치한다 (msstore·재부팅 코드 포함)

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. 부모 이슈 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)의 첫 태스크가 앱 단계 골격(`lib/Apps.psm1`)과 원천별 처리 함수 자리를 만들었다. `pc-setup/lib/AppWinget.psm1` 의 `Invoke-WingetApp` 은 지금 `throw '아직 구현되지 않은 원천: winget'` 이다. 이 태스크가 그것을 채운다.

정한 것:

- 확인은 `winget list --id <Id> -e` 의 종료 코드로 한다([앱 설치 선언 형식 비교: winget configure·winget import·직접 목록](https://github.com/hdmun/anything/issues/37)). 0 이면 설치됨, `0x8A150014`(`-1978335212`, 앱 없음)이면 없음이다(이 PC 에서 확인, 2026-11-11).
- **멱등 기준은 설치 여부만이다.** 설치는 `--no-upgrade` 로 한다. 업그레이드는 셋업 밖이다([앱 설치 선언 형식 정하기](https://github.com/hdmun/anything/issues/44) 「형식」).
- `Scope`(`machine`/`user`)는 `--scope` 로 넘긴다. machine 항목은 승격 단계(관리자 자식 프로세스)에서 불린다. 승격은 셋업 흐름이 정하므로 이 함수는 권한을 따지지 않는다.
- msstore 앱(`WingetSource = 'msstore'`)은 `--source msstore` 로 받고 `--scope` 를 넘기지 않는다. msstore ID: Docker Desktop `XP8CBJ40XLBWKX`, iCloud `9PKTQ5699M62`. 이 PC 에서 `winget list --id <ID> -e` 가 둘 다 0 이다.
- 설치가 `0x8A150109` 로 끝나면 재부팅이 필요한 것이다 → `할 일: 재부팅 후 셋업 다시 실행`. 셋업은 스스로 재부팅하지 않는다(#44 「재부팅·순서」).
- 비대화형으로 돈다. 동의 창에서 멈추면 셋업이 사람의 입력을 기다리며 끝나지 않는다.
- 설치한 앱이 PATH 를 바꿀 수 있으므로 `바꿈` 뒤에 `Update-SessionPath`(`lib/EnvPath.psm1`)를 부른다.

## 범위 밖 (건드리지 말 것)

- `Apps.psm1` 의 스키마·항목 만들기, 다른 원천 모듈(`AppScoop.psm1`·`AppRuntime.psm1`).
- winget 자체의 설치·보장: 2번 구현 이슈의 부트스트랩이 한다. 셋업에서 winget 이 없으면 `실패` 로 알리기만 한다.
- 업그레이드(`winget upgrade`), `winget pin`, `--version`.
- 실제 `apps.psd1`: 이 이슈의 마지막 태스크.

## 변경 대상 파일

- `pc-setup/lib/AppWinget.psm1` — 수정 (자리 → 구현)
- `pc-setup/tests/AppWinget.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/AppWinget.psm1
function Invoke-WingetApp {
    # → @{ Status; Detail }
    param([Parameter(Mandatory)]$Entry, [bool]$Check)
}

function Invoke-Winget {
    # winget 을 부르고 → @{ ExitCode = <int>; Output = <string[]> }. winget 이 없으면 ExitCode = $null.
    # 테스트는 이 함수를 Mock 한다(-ModuleName AppWinget).
    param([Parameter(Mandatory)][string[]]$Arguments)
}

Export-ModuleMember -Function Invoke-WingetApp, Invoke-Winget
```

## 동작 명세

### 정상 경로

**인자**

- 확인: `list --id <Id> -e --accept-source-agreements --disable-interactivity` 에 원천 인자를 붙인다. msstore 면 `--source msstore`, 아니면 `--source winget`.
- 설치: `install --id <Id> -e --no-upgrade --silent --accept-package-agreements --accept-source-agreements --disable-interactivity` 에 원천 인자를 붙인다. msstore 가 아니면 `--scope <Scope>` 도 붙인다.

**흐름**

1. `Invoke-Winget` 로 확인한다.
   - `ExitCode` 가 `$null` → `실패: winget 이 없다`.
   - 0 → `그대로`.
   - `0x8A150014` → 없음.
   - 그 밖 → `실패: winget list 종료 코드 0x<8자리 16진수>`.
2. 없음이고 `-Check` 면 `다름 (설치 안 됨)`.
3. 없음이고 고치는 실행이면 설치한다.
   - 0 → `Update-SessionPath` 를 부르고 `바꿈`.
   - `0x8A150109` → `Update-SessionPath` 를 부르고 `할 일: 재부팅 후 셋업 다시 실행`.
   - 그 밖 → `실패: winget install 종료 코드 0x<8자리 16진수>`. 출력에 오류 설명 줄이 있으면 마지막 비어 있지 않은 줄을 ` (<줄>)` 로 붙인다.
- 종료 코드 16진수는 32비트 부호 없는 값으로 적는다(`-1978335212` → `0x8A150014`).
- `Invoke-Winget` 은 진행 출력을 화면에 그대로 흘려도 되지만, 결과 판정은 종료 코드로만 한다(출력 문구는 Windows 표시 언어에 따라 바뀐다).

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다(`Mock -ModuleName AppWinget Invoke-Winget`, `Mock -ModuleName AppWinget Update-SessionPath`). **열거하지 않은 경우는 범위 밖이다**(예: 설치는 성공했는데 다시 확인하면 없는 경우, 같은 ID 가 두 소스에 있는 경우의 고르기).

| # | 상황 | `-Check` | 기대 |
|---|---|---|---|
| 1 | list 0 | 둘 다 | 그대로, install 안 불림 |
| 2 | list `0x8A150014` | 예 | 다름 (설치 안 됨), install 안 불림 |
| 3 | list `0x8A150014`, install 0 | 아님 | 바꿈, `Update-SessionPath` 1번 |
| 4 | install `0x8A150109` | 아님 | 할 일: 재부팅 후 셋업 다시 실행 |
| 5 | install `0x8A150056`(ElevationProhibited) | 아님 | `실패: winget install 종료 코드 0x8A150056` |
| 6 | list `0x8A15000F` 같은 그 밖의 코드 | 둘 다 | `실패: winget list 종료 코드 0x8A15000F` |
| 7 | winget 없음(`ExitCode $null`) | 둘 다 | 실패: winget 이 없다 |
| 8 | `Scope='machine'` | 아님 | install 인자에 `--scope machine`·`--source winget`·`--no-upgrade` |
| 9 | msstore | 아님 | 인자에 `--source msstore`, `--scope` 없음 |
| 10 | 모든 호출 | 둘 다 | `--accept-source-agreements`·`--disable-interactivity` 가 들어감, install 에는 `--accept-package-agreements` 도 |

`Invoke-Winget` 자체: `Get-Command winget` 이 없으면 `ExitCode $null` 을 돌려준다(테스트는 `Mock Get-Command`).

### 에러 처리

- 예상하지 못한 예외는 잡지 않는다. 셋업 흐름이 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `pc-setup/lib/Apps.psm1` — `Invoke-WingetApp` 을 부르는 자리, `Entry` 의 키(`Id`·`Scope`·`WingetSource`).
- `pc-setup/lib/EnvPath.psm1` — `Update-SessionPath`.
- `pc-setup/lib/WindowsSettings.psm1` — 결과 `@{ Status; Detail }` 를 돌려주는 모양.

## 인수 조건

- [ ] 엣지 케이스 표 1~10 과 `Invoke-Winget` 의 winget 없음이 각각 테스트로 있다.
- [ ] 테스트가 실제 winget 을 부르지 않는다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 `winget install`·`upgrade`·`uninstall` 을 돌리는 것(`winget list` 확인은 된다).
- 출력 문구(「설치된 패키지를 찾을 수 없습니다」 등)로 설치 여부를 판정하는 것.
- 이미 있는 앱을 업그레이드하는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
