> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/108
> updatedAt: 2026-11-20T06:24:03Z

# 저장소 도구 단계와 rdp-notify 의 install.ps1 을 만든다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다(단계 계약, 승격 단계, 항목 스크립트 규칙). 이 이슈의 부모는 [pc-setup 설정 파일과 저장소 도구](https://github.com/hdmun/anything/issues/105)이다. 앞 태스크까지 단계 순서가 Windows 설정 → 앱 → 설정 파일이 됐다.

이 태스크는 마지막 단계인 **저장소 도구** 단계를 만들고 첫 도구 rdp-notify 를 올린다([셋업이 저장소 도구를 설치하는 방식 정하기](https://github.com/hdmun/anything/issues/41) 와 그 정정).

- 저장소 도구는 이 저장소 안의 도구 가운데 PC 에 설치해야 쓸 수 있는 것이다. 정정([에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64)) 뒤로 rdp-notify 와 `.githooks` 둘이다. `.githooks` 는 다음 태스크다.
- 도구 폴더마다 `install.ps1` 을 둔다. 셋업은 선언의 도구 목록 순서대로 부른다. 도구끼리는 의존이 없고, 하나가 실패해도 계속한다.
- `install.ps1` 은 1번 이슈의 항목 스크립트 규칙을 따른다: `param([switch]$Check)`, 저장소 경로는 `$PSScriptRoot`, 상태를 먼저 보고 다를 때만 고침, 마지막 출력 줄 하나가 결과.
- env 파일이 없으면 설치는 하고 `할 일` 로 알린다. 견본(`*.env.example`)은 복사하지 않는다. 가짜 값이 든 파일은 빠진 파일보다 찾기 어렵기 때문이다.
- rdp-notify 만 승격이 필요하다. 작업 스케줄러의 `RdpNotify` 작업은 SYSTEM 작업이라 **등록뿐 아니라 상태 읽기도** 관리자 창에서만 된다. 일반 창의 `Get-ScheduledTask` 는 이 작업을 찾지 못한다(`rdp-notify/README.md` 「문제 해결」). 그래서 확인과 등록을 모두 승격된 쪽에서 하고, rdp-notify 는 고치는 실행마다 승격 단계에 든다([부트스트랩 진입점과 관리자 권한 처리 정하기](https://github.com/hdmun/anything/issues/42) 「UAC·`-Check`·재부팅」). 일반 권한의 `-Check` 결과는 `확인 못 함: 관리자 필요` 다.
- 원격 데스크톱 켜기는 Windows 설정 단계의 `RemoteDesktop` 이 맡는다. rdp-notify 의 `install.ps1` 은 원격 데스크톱을 건드리지 않는다([Windows 설정을 선언에 넣을지 정하기](https://github.com/hdmun/anything/issues/63) 「원격 데스크톱」).

기존 rdp-notify(`rdp-notify/`):

- `register.ps1`: 관리자가 아니면 안내문을 출력하고 `exit 1`. 알림 스크립트가 없으면 `exit 1`. `Register-ScheduledTask -TaskName RdpNotify -Xml (New-TaskXml) -Force` 로 등록하거나 교체한다. env 파일(`rdp-notify.env`)이 없으면 「주의」 문장만 출력한다. `-PrintXml` 은 관리자 권한 없이 작업 XML 만 출력한다. 작업 XML 의 동작 인수에는 `rdp-notify.ps1` 의 **절대 경로**가 들어간다(그래서 저장소를 옮기면 다시 등록해야 한다).
- `rdp-notify.env` 는 gitignore 대상이고 웹훅 URL 이 든다. `rdp-notify.env.example` 이 견본이다.
- 이 폴더의 `.ps1` 은 UTF-8 **BOM 포함**으로 저장한다(Windows PowerShell 5.1 의 한글 깨짐 때문, `rdp-notify/README.md` 「바꿀 때」).

이 PC 에서는 셋업(고치는 실행)을 돌리지 않는다. 이 PC 의 `RdpNotify` 작업을 등록·교체·제거하지 않는다. 테스트는 `Mock` 으로 한다.

## 범위 밖 (건드리지 말 것)

- `rdp-notify/register.ps1`·`rdp-notify/rdp-notify.ps1`·`rdp-notify.env.example` 의 동작.
- `rdp-notify/README.md`: 마지막 태스크(경로)에서 고친다. 이 태스크는 고치지 않는다.
- `.githooks` 도구: 다음 태스크.
- 원격 데스크톱 설정, 방화벽.
- agent-rules·relay·agent-accounts 의 설치(셋업 밖, 손으로 한다).

## 변경 대상 파일

- `pc-setup/lib/RepoTools.psm1` — 신규
- `pc-setup/repo-tools.psd1` — 신규 (rdp-notify 한 줄)
- `rdp-notify/install.ps1` — 신규 (UTF-8 BOM 포함)
- `pc-setup/lib/Setup.psm1` — 수정 (`$script:DefaultStageProviders` 맨 끝에 저장소 도구 단계 추가)
- `pc-setup/tests/AppsDeclaration.Tests.ps1` — 수정 ('Setup 기본 단계 등록' 테스트만: 기본 단계 수 단언을 `3` → `4` 로, 넷째 단계가 `저장소 도구` 임을 확인. `Get-RepoToolItems` 모킹(Stage `저장소 도구`, Id `FakeRepoTool`)을 더하고 `Results.Count` 를 `4` 로, `Results[3]` 의 Stage·Id 를 단언한다. 다른 테스트는 건드리지 않는다)
- `pc-setup/tests/RepoTools.Tests.ps1` — 신규
- `pc-setup/tests/RdpNotifyInstall.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/RepoTools.psm1

function Get-RepoToolItems {
    # <Root>\repo-tools.psd1 을 읽고 검사해 항목 목록을 돌려준다.
    # 항목: Stage = '저장소 도구', Id = 선언의 Id, Elevated = [bool]$item.Elevated,
    #       Invoke = { param($Check) Invoke-ItemScript -Path <저장소>\<Id>\install.ps1 -Check:$Check }
    # <저장소> = Split-Path $Root -Parent. 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)
}

Export-ModuleMember -Function Get-RepoToolItems
```

```powershell
# pc-setup/repo-tools.psd1
@{
    Items = @(
        @{ Id = 'rdp-notify'; Elevated = $true }
    )
}
```

```powershell
# pc-setup/lib/Setup.psm1 — 단계 목록 맨 끝(설정 파일 단계 뒤)에 더한다
{ param($Root) Get-RepoToolItems -Root $Root }
```

```powershell
# rdp-notify/install.ps1
[CmdletBinding()]
param([switch]$Check)
# 함수로 나눈다(테스트가 dot-source 한 뒤 Mock 한다). 본문은 dot-source 가 아닐 때만 돈다:
#   if ($MyInvocation.InvocationName -ne '.') { Invoke-Main -Check:$Check }
function Test-Admin { }                      # 관리자 토큰이면 $true
function Get-RdpNotifyTask { }               # Get-ScheduledTask -TaskName RdpNotify -ErrorAction SilentlyContinue
function Get-ExpectedArguments { }           # & "$PSScriptRoot\register.ps1" -PrintXml 의 XML 에서 Actions/Exec/Arguments 글
function Invoke-Register { }                 # & "$PSScriptRoot\register.ps1" 을 부르고 $LASTEXITCODE 를 돌려준다
function Test-EnvFile { }                    # Test-Path "$PSScriptRoot\rdp-notify.env"
function Invoke-Main { param([switch]$Check) }
```

## 동작 명세

### 선언 스키마 (`repo-tools.psd1`)

- `Key = 'Id'`, `Required = @('Id')`, `Allowed = @('Id','Elevated')`.
- `Validate`: `Elevated` 는 `$true`/`$false`. `Id` 가 절대 경로이거나 `..` 을 포함하면 `Id 는 저장소 루트 기준 폴더 이름이다`.
- `Get-RepoToolItems` 는 `Read-Declaration` 뒤에 항목마다 `<저장소>\<Id>\install.ps1` 이 있는지 본다. 없으면 `repo-tools.psd1:<줄>: install.ps1 이 없다: <Id>/install.ps1` 문제를 더해 `DeclarationException` 을 던진다.

### `rdp-notify/install.ps1` 의 `Invoke-Main`

작업이 「선언과 같다」는 것은 셋 모두 참인 것이다: 작업이 있다, 작업의 첫 동작 `Arguments` 가 `Get-ExpectedArguments` 와 글자까지 같다(저장소를 옮기면 달라진다), 작업 `State` 가 `Disabled` 가 아니다.

| # | 상황 | `-Check` | 고치는 실행 |
|---|---|---|---|
| 1 | 관리자 아님 | `확인 못 함: 관리자 필요` | `실패: 관리자 필요` |
| 2 | 작업이 선언과 같다, env 파일 있음 | `그대로` | `그대로` |
| 3 | 작업 없음 | `다름 (작업 없음)` | `Invoke-Register` → 0 이면 다음 줄의 env 판정으로 |
| 4 | 인수 다름(저장소 옮김) | `다름 (작업 경로 다름)` | 3 과 같다 |
| 5 | 작업이 꺼짐(`Disabled`) | `다름 (작업 꺼짐)` | 3 과 같다 |
| 6 | `Invoke-Register` 가 0 이 아님 | — | `실패: register.ps1 종료 코드 <n>` |
| 7 | 등록 성공, env 파일 있음 | — | `바꿈` |
| 8 | env 파일 없음(작업 상태와 상관없이, 1·6 이 아닐 때) | `할 일: <env 전체 경로> 만들기 (rdp-notify/README.md 설치 1~2번)` | 작업을 맞춘 뒤 같은 `할 일` |

- 8번이 2·3·4·5·7 보다 우선한다. 결과 줄이 하나라서, 작업을 고쳤어도 env 파일이 없으면 `할 일` 로 끝난다. 두 번째 고치는 실행에서도 env 파일이 없으면 `할 일` 이다(멱등 판정의 `바꿈`·`실패` 0 을 깨지 않는다).
- `-Check` 는 `Invoke-Register` 를 부르지 않는다. `Get-ExpectedArguments`(`-PrintXml`)는 관리자 권한 없이 돈다.
- `register.ps1` 의 화면 출력(`Write-Host`)은 그대로 둔다. 결과 줄은 `install.ps1` 마지막의 `Write-Output` 한 줄이다.
- `rdp-notify.env.example` 을 복사하지 않는다. env 파일을 만들지 않는다.

### 엣지 케이스

`RdpNotifyInstall.Tests.ps1` 은 `install.ps1` 을 dot-source 해 함수를 얻고, `Test-Admin`·`Get-RdpNotifyTask`·`Get-ExpectedArguments`·`Invoke-Register`·`Test-EnvFile` 을 `Mock` 한 뒤 `Invoke-Main` 을 부른다. 가짜 작업은 `[pscustomobject]@{ State = 'Ready'; Actions = @([pscustomobject]@{ Arguments = '...' }) }` 모양이다. 위 표 1~8 을 `-Check`·고치는 실행 각각 해당하는 칸마다 테스트로 둔다. 더해서:

- `-Check` 와 1번에서 `Invoke-Register` 가 한 번도 불리지 않는다.
- 3번 고치는 실행에서 `Invoke-Register` 가 정확히 한 번 불린다.
- `Get-ExpectedArguments` 의 실제 구현이 `register.ps1 -PrintXml` 출력에서 `rdp-notify.ps1` 의 전체 경로가 든 인수 글을 꺼낸다(Mock 없이 한 번 부른다. 관리자 권한이 필요 없다).
- `install.ps1` 파일이 UTF-8 BOM(`EF BB BF`)으로 시작한다.

`RepoTools.Tests.ps1`(`TestDrive:` 에 가짜 저장소: `<가짜>\pc-setup\repo-tools.psd1`, `<가짜>\tool-a\install.ps1`):

- 정상 두 줄(하나는 `Elevated`) → 항목 2개, `Elevated` 맞음, `Invoke` 가 그 `install.ps1` 의 결과를 돌려줌(`-Check` 전달 포함).
- `install.ps1` 없음 → 「install.ps1 이 없다」.
- `Id = '..\x'` → 「저장소 루트 기준 폴더 이름」.
- 모르는 키(`Script`) → 모르는 키 문제.
- 저장소 `pc-setup/repo-tools.psd1` 이 검사를 통과하고 Id 가 `rdp-notify` 하나, `Elevated` 다.
- 기본 단계 목록으로 만든 항목의 `Stage` 순서가 `Windows 설정` → `앱` → `설정 파일` → `저장소 도구` 다.

**열거하지 않은 경우는 범위 밖이다**(예: 작업 트리거·보안 주체가 바뀐 경우, env 파일 내용 검사, 작업이 두 개인 경우).

### 에러 처리

- 예상하지 못한 예외는 잡지 않아도 된다. `Invoke-ItemScript` 가 `실패: <메시지>` 로 바꾼다.

## 기존 코드 참조

- `rdp-notify/register.ps1` — 감쌀 스크립트. `-PrintXml`, 관리자 검사(`Test-Admin`), `exit` 코드, env 파일 「주의」 문장.
- `rdp-notify/README.md` — 설치 1~2번(env 파일 만들기), 「문제 해결」(일반 창에서 작업이 안 보임).
- `pc-setup/lib/ConfigFiles.psm1`·`pc-setup/lib/WindowsSettings.psm1` — 단계 모듈 모양과 파일 존재 검사 문제 모으기.
- `pc-setup/windows/RemoteDesktop.ps1` — dot-source 시험 방식(`$MyInvocation.InvocationName`)과 항목 스크립트 결과 줄.
- `pc-setup/lib/ItemScript.psm1` — `Invoke-ItemScript`.

## 인수 조건

- [ ] 표 1~8 과 엣지 케이스 목록이 각각 테스트로 있다.
- [ ] 테스트 중 이 PC 의 `RdpNotify` 작업을 등록·교체·제거하지 않는다(`Invoke-Register` Mock).
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC(일반 권한)에서 `[저장소 도구] rdp-notify: 확인 못 함: 관리자 필요` 를 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- `register.ps1` 을 고치거나, 등록 로직을 `install.ps1` 에 다시 쓰는 것.
- 견본 env 파일을 복사하는 것, env 파일을 만드는 것.
- 원격 데스크톱·방화벽을 건드리는 것.
- 이 PC 에서 `install.ps1` 이나 셋업을 `-Check` 없이 돌리는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
