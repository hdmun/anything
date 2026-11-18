> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/96
> updatedAt: 2026-11-17T11:56:33Z

# scoop 원천으로 앱을 확인하고 설치한다 (scoop 설치·버킷 포함)

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」에 있다. 부모 이슈 [pc-setup 앱: 패키지 관리자 원천](https://github.com/hdmun/anything/issues/93)의 첫 태스크가 앱 단계 골격(`lib/Apps.psm1`)을 만들었다. `pc-setup/lib/AppScoop.psm1` 의 `Invoke-ScoopApp` 은 지금 `throw '아직 구현되지 않은 원천: scoop'` 이다. 이 태스크가 그것을 채운다.

scoop 은 winget 이 7일 넘게 뒤처진 앱의 보조 **원천**이다. scoop 앱은 lazygit(extras)·cmake(main)·dbeaver(extras)·nano(main)이고([앱 목록 선별하기](https://github.com/hdmun/anything/issues/43#issuecomment-6704619964)), Node 를 다루는 nvm v2 도 scoop `nvm`(main)으로 받는다([런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62)). 선언 줄 예: `@{ Id = 'lazygit'; Origin = 'scoop'; Bucket = 'extras' }`.

정한 것:

- scoop 은 사용자 범위 설치이고 항상 일반 권한으로 돈다. 관리자 창에서는 설치하지 않는다(기본 설치 스크립트가 관리자 실행을 막는다)([부트스트랩 진입점과 관리자 권한 처리 정하기](https://github.com/hdmun/anything/issues/42) 「새 입력」). 셋업 흐름이 관리자 창에서 멈추므로 고치는 실행은 일반 권한이다.
- 새 PC 에는 scoop 이 없다. 첫 scoop 항목을 처리할 때 scoop 을 설치하고, 그 항목의 버킷이 없으면 추가한 뒤 앱을 설치한다(scoop 설치·버킷·앱 순서, #42 「셋업」 3).
- 설치 여부만 맞춘다. 업그레이드(`scoop update`)는 셋업 밖이다.
- 손으로 더한 버킷과 다른 원천으로 두 벌 설치된 앱은 셋업이 모른다([선언에 없는 앱(드리프트) 처리 정하기](https://github.com/hdmun/anything/issues/65)).
- scoop shims 는 사용자 PATH 에 들어간다. scoop 설치 뒤와 앱 설치 뒤에는 `Update-SessionPath`(`lib/EnvPath.psm1`)를 부른다.

이 PC 에서 확인한 사실(2026-11-11): scoop 이 `~/scoop` 에 있고 버킷은 `main` 하나, 앱은 `nano` 하나다. `scoop prefix nano` 는 경로를 출력하고 종료 코드 0, `scoop prefix lazygit` 은 `Could not find app path for 'lazygit'.` 와 종료 코드 1 이다. `scoop bucket list` 는 `Name` 속성을 가진 객체를 돌려준다.

## 범위 밖 (건드리지 말 것)

- `Apps.psm1` 의 스키마·항목 만들기, 다른 원천 모듈.
- `main`·`extras` 밖의 버킷, 버킷 제거, 앱 제거.
- nvm 으로 Node 를 설치하는 일: 넷째 태스크(`AppRuntime.psm1`). 이 태스크는 `nvm` 앱 자체를 scoop 앱으로 설치하는 데까지다.

## 변경 대상 파일

- `pc-setup/lib/AppScoop.psm1` — 수정 (자리 → 구현)
- `pc-setup/tests/AppScoop.Tests.ps1` — 신규
- `pc-setup/tests/Apps.Tests.ps1` — 수정 (테스트 17 '아직 구현되지 않은 원천 예외' 에서 scoop 항목만 뺀다. 나머지 원천 항목과 단언은 그대로 둔다)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/AppScoop.psm1
function Invoke-ScoopApp {
    # → @{ Status; Detail }
    param([Parameter(Mandatory)]$Entry, [bool]$Check)
}

function Invoke-Scoop {
    # scoop 을 부르고 → @{ ExitCode = <int>; Output = <object[]> }. scoop 이 없으면 ExitCode = $null.
    param([Parameter(Mandatory)][string[]]$Arguments)
}

function Install-Scoop {
    # 공식 설치 스크립트(https://get.scoop.sh)를 일반 권한으로 실행한다. 성공하면 $true.
}

Export-ModuleMember -Function Invoke-ScoopApp, Invoke-Scoop, Install-Scoop
```

테스트는 `Invoke-Scoop`·`Install-Scoop`·`Update-SessionPath` 를 `Mock -ModuleName AppScoop` 으로 바꾼다.

## 동작 명세

### 정상 경로

1. **scoop**: `Invoke-Scoop @('--version')` 의 `ExitCode` 가 `$null` 이면 scoop 이 없다.
   - `-Check` → `다름 (scoop 없음)`.
   - 고치는 실행 → `Install-Scoop`. 실패하면 `실패: scoop 설치 실패`. 성공하면 `Update-SessionPath` 를 부르고 계속한다.
2. **버킷**: `Invoke-Scoop @('bucket','list')` 의 `Output` 에서 `Name` 목록을 얻는다. 항목의 `Bucket` 이 없으면
   - `-Check` → `다름 (버킷 <Bucket> 없음)`.
   - 고치는 실행 → `Invoke-Scoop @('bucket','add',<Bucket>)`. 종료 코드가 0 이 아니면 `실패: scoop bucket add <Bucket> 종료 코드 <n>`.
3. **앱**: `Invoke-Scoop @('prefix',<Id>)` 종료 코드 0 이면 설치됨.
   - 설치됨이고 1·2 에서 아무것도 바꾸지 않았으면 `그대로`.
   - 없음이고 `-Check` → `다름 (설치 안 됨)`. (1 에서 scoop 이 없으면 2·3 은 보지 않는다.)
   - 없음이고 고치는 실행 → `Invoke-Scoop @('install',"<Bucket>/<Id>")`. 0 이면 `Update-SessionPath` 후 `바꿈`, 아니면 `실패: scoop install <Bucket>/<Id> 종료 코드 <n>`.
4. 고치는 실행에서 1·2 만 바꾸고 앱은 이미 있었다면 `바꿈`.

- `Invoke-Scoop` 은 같은 셋업 실행 안에서 scoop 설치 여부와 버킷 목록을 다시 묻지 않아도 되도록 결과를 모듈 변수에 기억해도 된다. 기억한다면 버킷을 추가하거나 scoop 을 설치한 뒤에는 갱신한다.
- `Install-Scoop` 은 `Invoke-RestMethod https://get.scoop.sh | Invoke-Expression` 에 해당하는 일을 한다. 관리자 창이면 설치하지 않고 `$false` 를 돌려준다(`Test-AdminWindow`, `lib/Elevation.psm1`).

### 엣지 케이스

경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 같은 이름 앱이 다른 버킷에 있는 경우, scoop 설치 경로를 `$env:SCOOP` 로 바꾼 경우).

| # | 상황 | `-Check` | 기대 |
|---|---|---|---|
| 1 | scoop 있음, 버킷 있음, 앱 있음 | 둘 다 | 그대로, install·bucket add 안 불림 |
| 2 | 앱 없음 | 예 | 다름 (설치 안 됨) |
| 3 | 앱 없음, install 0 | 아님 | 바꿈, install 인자 `install extras/lazygit`, `Update-SessionPath` 불림 |
| 4 | 버킷 없음 | 예 | 다름 (버킷 extras 없음) |
| 5 | 버킷 없음, 앱 없음 | 아님 | bucket add → install 순서, 바꿈 |
| 6 | bucket add 실패 | 아님 | 실패, install 안 불림 |
| 7 | scoop 없음 | 예 | 다름 (scoop 없음), `Install-Scoop` 안 불림 |
| 8 | scoop 없음 | 아님 | `Install-Scoop` → bucket add → install, 바꿈 |
| 9 | `Install-Scoop` 이 `$false` | 아님 | 실패: scoop 설치 실패 |
| 10 | install 종료 코드 1 | 아님 | `실패: scoop install main/cmake 종료 코드 1` |
| 11 | 버킷만 없고 앱은 있음 | 아님 | bucket add 후 바꿈 |

### 에러 처리

- 예상하지 못한 예외는 잡지 않는다. 셋업 흐름이 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `pc-setup/lib/AppWinget.psm1` — 같은 모양의 원천 모듈(외부 명령을 감싼 함수, 결과 모양, 테스트의 Mock 방식).
- `pc-setup/lib/EnvPath.psm1` — `Update-SessionPath`.
- `pc-setup/lib/Elevation.psm1` — `Test-AdminWindow`.

## 인수 조건

- [ ] 엣지 케이스 표 1~11 이 각각 테스트로 있다.
- [ ] 테스트가 실제 scoop 을 부르지 않고 scoop 을 설치하지 않는다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 `scoop install`·`bucket add`·`update` 를 돌리는 것(`scoop prefix`·`bucket list` 확인은 된다).
- 출력 문구로 설치 여부를 판정하는 것(`prefix` 의 종료 코드를 쓴다).
- 관리자 권한으로 scoop 을 설치하는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
