> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/86
> updatedAt: 2026-11-11T11:47:08Z

# Windows 설정 단계와 레지스트리 값 8개를 더한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 전체 설계는 부모 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다. 앞 태스크까지 선언 읽기(`lib/Declaration.psm1`), 결과·요약(`lib/Report.psm1`), 항목 스크립트 실행(`lib/ItemScript.psm1`), 셋업 흐름과 승격 단계(`lib/Setup.psm1`·`lib/Elevation.psm1`)가 생겼다. 아직 단계가 하나도 없다(`$script:DefaultStageProviders` 가 비어 있음).

이 태스크는 첫 단계인 **Windows 설정** 단계를 만든다([Windows 설정을 선언에 넣을지 정하기](https://github.com/hdmun/anything/issues/63)).

- 선언 파일 `pc-setup/windows-settings.psd1`, 한 줄 한 설정. 레지스트리 값 하나는 `Id`·`Path`·`Name`·`Type`·`Value` 로 쓴다. `Path` 가 `HKLM:` 이면 **승격 단계**에서 처리한다.
- 목록으로 못 쓰는 설정은 `Script = $true`(필요하면 `Elevated = $true`)로 두고 `pc-setup/windows/<Id>.ps1` 에 쓴다. 이 태스크는 그 연결까지만 만든다. 실제 스크립트 3개와 그 선언 줄은 다음 태스크다.
- 값을 쓴 뒤 `WM_SETTINGCHANGE` 알림을 보낸다. 탐색기는 다시 시작하지 않는다. 결과는 `바꿈` 이고 `할 일` 은 만들지 않는다.
- 손으로 바꾼 선언 값은 셋업 재실행 때 선언값으로 되돌린다(`바꿈`). 선언에 없는 Windows 설정은 건드리지 않는다.
- `-Check` 에 필요한 HKLM 값은 일반 권한으로 읽힌다(이 PC 에서 확인).

5.1 실행 정책 줄을 넣는 이유: WT 기본 프로필이 Windows PowerShell 5.1 이고, 손으로 만든 5.1 프로필이 새 Windows 기본값(`Restricted`)에서는 로드되지 않는다([에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64) 정정).

## 범위 밖 (건드리지 말 것)

- `windows/RemoteDesktop.ps1`·`windows/Hibernate.ps1`·`windows/Power.ps1` 과 그 선언 줄: 다음 태스크.
- 앱·설정 파일·저장소 도구 단계: 3·5번 구현 이슈.
- 선언 표에 없는 Windows 설정(시각 효과·NumLock·저장소 센스 등).
- 이 PC 의 실제 레지스트리를 바꾸는 테스트.

## 변경 대상 파일

- `pc-setup/lib/WindowsSettings.psm1` — 신규
- `pc-setup/windows-settings.psd1` — 신규
- `pc-setup/lib/Setup.psm1` — 수정 (`$script:DefaultStageProviders` 에 Windows 설정 단계 추가)
- `pc-setup/tests/WindowsSettings.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/lib/WindowsSettings.psm1

function Get-WindowsSettingItems {
    # <Root>\windows-settings.psd1 을 읽고 검사해 항목 목록을 돌려준다(Stage = 'Windows 설정').
    # 문제가 있으면 DeclarationException.
    param([Parameter(Mandatory)][string]$Root)
}

function Invoke-RegistrySetting {
    # 레지스트리 값 하나를 확인하거나 맞춘다 → @{ Status; Detail }
    param(
        [Parameter(Mandatory)]$Entry,     # Path, Name, Type, Value 를 가진 객체
        [bool]$Check
    )
}

function Send-SettingChange {
    # WM_SETTINGCHANGE 를 모든 최상위 창에 보낸다(SendMessageTimeout, HWND_BROADCAST, SMTO_ABORTIFHUNG, 5초). 테스트는 Mock 한다.
}

Export-ModuleMember -Function Get-WindowsSettingItems, Invoke-RegistrySetting, Send-SettingChange
```

`Setup.psm1` 의 기본 단계 목록은 이렇게 된다:

```powershell
$script:DefaultStageProviders = @(
    { param($Root) Get-WindowsSettingItems -Root $Root }
)
```

## 동작 명세

### 선언 스키마

- `Key = 'Id'`, `Required = @('Id')`, `Allowed = @('Id','Path','Name','Type','Value','Script','Elevated')`, `Enums = @{ Type = @('DWord','String') }`.
- `Validate`(항목 하나):
  - `Script` 가 `$true` 면 `Path`·`Name`·`Type`·`Value` 가 없어야 한다 → 있으면 `스크립트 항목에는 '<키>' 를 쓰지 않는다`.
  - `Script` 가 없으면 `Path`·`Name`·`Type`·`Value` 가 모두 있어야 한다 → 빠지면 `레지스트리 항목에 '<키>' 가 없다`. `Elevated` 는 쓰지 않는다 → `레지스트리 항목의 승격 여부는 Path 로 정한다`. `Path` 는 `HKLM:\` 또는 `HKCU:\` 로 시작해야 한다 → 아니면 `Path 는 HKLM:\ 또는 HKCU:\ 로 시작한다`.
  - `Script`·`Elevated` 값은 `$true`/`$false` 여야 한다.
- `Get-WindowsSettingItems` 는 `Read-Declaration` 뒤에 `Script` 항목마다 `<Root>\windows\<Id>.ps1` 이 있는지 본다. 없으면 `windows-settings.psd1:<줄>: 스크립트가 없다: windows/<Id>.ps1` 문제를 더해 `DeclarationException` 을 던진다(다른 문제와 함께 모은다).

### 항목

- 레지스트리 항목: `Elevated = $Path.StartsWith('HKLM:')`, `Invoke = { param($Check) Invoke-RegistrySetting -Entry <항목> -Check $Check }`.
- 스크립트 항목: `Elevated = [bool]$item.Elevated`, `Invoke = { param($Check) Invoke-ItemScript -Path <Root>\windows\<Id>.ps1 -Check:$Check }`.
- 항목 순서는 선언 순서다.

### `Invoke-RegistrySetting`

| 상황 | `-Check` | 고치는 실행 |
|---|---|---|
| 값이 선언과 같다(종류·값 모두) | `그대로` | `그대로` |
| 키나 값이 없다 | `다름 (없음)` | 키를 만들고(`New-Item -Force`) 값을 쓴 뒤 `바꿈` |
| 값이 다르다 | `다름 (지금 <현재>, 선언 <값>)` | 값을 쓴 뒤 `바꿈` |
| 종류가 다르다(예: String 자리에 DWord) | `다름 (종류 <현재 종류>, 선언 <Type>)` | 선언 종류로 다시 쓴 뒤 `바꿈` |
| 읽기에서 권한 오류(`UnauthorizedAccessException`·`SecurityException`) | `확인 못 함: 관리자 필요` | `실패: 관리자 필요` |
| 쓰기에서 오류 | — | `실패: <예외 메시지>` |

- 값 비교: DWord 는 정수로, String 은 대소문자를 구분하는 문자열로 비교한다. 종류는 `(Get-Item <Path>).GetValueKind(<Name>)` 로 읽는다.
- 값을 쓴 뒤(`바꿈`) `Send-SettingChange` 를 한 번 부른다.
- `-Check` 는 아무것도 쓰지 않고 `Send-SettingChange` 도 부르지 않는다.

### `windows-settings.psd1` (8줄, 이 순서)

Windows 설정 결정의 표에서 레지스트리 값 줄만 옮긴다. 다음 태스크가 스크립트 3줄(`RemoteDesktop`·`Hibernate`·`Power`)을 `LongPaths` 와 `ShowFileExtensions` 사이에 넣는다.

| Id | Path | Name | Type | Value |
|---|---|---|---|---|
| `PowerShell51ExecutionPolicy` | `HKCU:\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell` | `ExecutionPolicy` | String | `RemoteSigned` |
| `DeveloperMode` | `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock` | `AllowDevelopmentWithoutDevLicense` | DWord | 1 |
| `LongPaths` | `HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem` | `LongPathsEnabled` | DWord | 1 |
| `ShowFileExtensions` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `HideFileExt` | DWord | 0 |
| `ShowHiddenFiles` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `Hidden` | DWord | 1 |
| `DarkModeApps` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `AppsUseLightTheme` | DWord | 0 |
| `DarkModeSystem` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize` | `SystemUsesLightTheme` | DWord | 0 |
| `TaskbarSearchIcon` | `HKCU:\Software\Microsoft\Windows\CurrentVersion\Search` | `SearchboxTaskbarMode` | DWord | 1 |

### 엣지 케이스

`Invoke-RegistrySetting` 은 Pester `TestRegistry:` 아래 경로로 시험한다(`Entry.Path = 'TestRegistry:\...'` 로 직접 만든다. 스키마의 `HKLM:`/`HKCU:` 규칙은 `Get-WindowsSettingItems` 에만 적용된다). 위 표의 6행과 아래를 각각 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: `QWord`·`ExpandString`·`MultiString`, 기본값(`(default)`) 이름).

- DWord 같음 / 다름 / 없음(키 없음) / 없음(키는 있고 값 없음)
- String 같음 / 대소문자만 다름(`remotesigned`) → 다름
- 종류 다름
- 읽기 권한 오류(`Mock Get-ItemProperty` 또는 `Get-Item` 이 `UnauthorizedAccessException` 을 던짐) → `-Check` 는 `확인 못 함: 관리자 필요`
- 고치는 실행에서 값을 쓴 뒤 `Send-SettingChange` 가 1번 불림, `그대로` 일 때와 `-Check` 일 때는 0번

`Get-WindowsSettingItems`(`TestDrive:` 에 가짜 `Root`):

- 레지스트리 줄 HKLM → `Elevated = $true`, HKCU → `$false`
- 스크립트 줄 + `windows/<Id>.ps1` 있음 → 항목, `Invoke` 가 그 스크립트의 결과를 돌려줌
- 스크립트 줄 + 스크립트 없음 → `DeclarationException` 에 「스크립트가 없다」
- `Validate` 의 문제 문구 다섯 가지 각각

실제 선언:

- 저장소의 `pc-setup/windows-settings.psd1` 이 검사를 통과하고, Id 8개가 위 표의 순서이며, `DeveloperMode`·`LongPaths` 만 `Elevated` 다.

### 에러 처리

- 한 항목의 오류는 그 항목의 결과로만 남는다(셋업 흐름이 다음 항목으로 넘어간다).

## 기존 코드 참조

- `pc-setup/lib/Declaration.psm1` — `Read-Declaration`·`DeclarationException`. 스키마 해시테이블 모양.
- `pc-setup/lib/ItemScript.psm1` — `Invoke-ItemScript`.
- `pc-setup/lib/Setup.psm1` — `$script:DefaultStageProviders`, 항목 객체 모양(`Stage`·`Id`·`Elevated`·`Invoke`).
- `pc-setup/tests/Setup.Tests.ps1` — 실제 `-Check` 통합 테스트. 이 태스크 뒤로는 Windows 설정 8줄이 이 PC 에서 확인된다(`다름` 은 허용, `실패` 는 안 됨).

## 인수 조건

- [ ] 엣지 케이스 목록이 각각 테스트로 있다.
- [ ] 테스트가 이 PC 의 실제 `HKCU:`·`HKLM:` 값을 쓰지 않는다(`TestRegistry:` 만 쓴다).
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 Windows 설정 8줄을 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 고치는 실행을 돌리는 것, 실제 레지스트리를 쓰는 테스트.
- 탐색기를 다시 시작하는 것, `할 일` 을 만드는 것.
- 선언 표에 없는 설정을 더하는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
