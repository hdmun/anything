# 앱 설치 선언 형식 비교: winget configure · winget import · 직접 목록

- 이슈: hdmun/anything#37 (상위 지도 #36)
- 조사일: 2026-11-07
- 기준 버전: winget v1.29.380 (2026-09-21 안정판, 이 PC 설치본과 같음), PowerShell 7.6.9. 소스 인용은 태그 `v1.29.380` 기준이다.
- 범위: 문서·소스 읽기와 이 PC 에서의 읽기 전용 명령(`--help`, `winget list`, 임시 폴더로 `winget export`, `winget dscv3 package --schema`)만 했다. 설치·구성 적용은 하지 않았다.
- 용어: `pc-setup/CONTEXT.md` 의 **선언**, **셋업**, **부트스트랩**을 쓴다.

## 결론 먼저

- 이 저장소 조건(도구는 winget·PowerShell 7·git 만, 사람이 직접 고치는 목록, 몇 번을 다시 돌려도 결과가 같은 **셋업**)에는 **`.psd1` 목록 + 직접 만든 `winget install` 루프**가 가장 잘 맞는다.
- `winget configure`(DSC)는 동작 방식이 **선언**에 가장 가깝다. 없으면 설치하고, 있으면 건드리지 않고, 버전을 적으면 올리거나 내린다. UAC 는 1회이고 `configure test` 도 있다. 대신 앱을 하나 test 하는 데 8–16초가 들고, scope 를 지정할 수 없고, YAML 이 길어지고, DSC v3 처리기(Store 패키지)나 PSGallery 모듈이 따라 들어온다.
- `winget import` 는 코드가 가장 적다. 하지만 기본 동작이 "이미 있으면 최신으로 업그레이드"이고, `--ignore-unavailable` 없이 돌리면 패키지 하나만 못 찾아도 **아무것도 설치하지 않고** 멈춘다. 주석을 달 수 없고, 앱별 결과를 기계가 읽을 형태로 받을 수 없다.
- 세 방식 모두 실제 설치는 winget 의 같은 설치 흐름을 탄다. 차이는 세 가지에서 난다: 이미 설치된 앱을 어떻게 다루는지, 실패를 어떻게 모으는지, 관리자 권한을 어떻게 나누는지.

## 출처

| 약칭 | URL |
| --- | --- |
| [L-import] | https://learn.microsoft.com/en-us/windows/package-manager/winget/import (ms.date 2026-07-20) |
| [L-export] | https://learn.microsoft.com/en-us/windows/package-manager/winget/export (ms.date 2026-07-19) |
| [L-config] | https://learn.microsoft.com/en-us/windows/package-manager/configuration/ (ms.date 2026-11-02) |
| [L-create] | https://learn.microsoft.com/en-us/windows/package-manager/configuration/create (0.2 스키마) |
| [L-create-v3] | https://learn.microsoft.com/en-us/windows/package-manager/configuration/create-v3 (ms.date 2026-05-01) |
| [L-configure] | https://learn.microsoft.com/en-us/windows/package-manager/winget/configure |
| [L-dscv3] | https://learn.microsoft.com/en-us/windows/package-manager/winget/dscv3 |
| [L-pin] | https://learn.microsoft.com/en-us/windows/package-manager/winget/pinning |
| [L-psd1] | https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/import-powershelldatafile |
| [rc] | https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md |
| [rel-1.29.380] | https://github.com/microsoft/winget-cli/releases/tag/v1.29.380 |
| [rel-1.11.400] | https://github.com/microsoft/winget-cli/releases/tag/v1.11.400 |
| [schema-pkgs] | https://github.com/microsoft/winget-cli/blob/v1.29.380/schemas/JSON/packages/packages.schema.2.0.json |
| [src-DscPackage] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerCLICore/Commands/DscPackageResource.cpp |
| [src-WinGetDSC] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/PowerShell/Microsoft.WinGet.DSC/Microsoft.WinGet.DSC.psm1 , `.psd1` 같은 폴더 |
| [src-Processor] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/Microsoft.Management.Configuration.Processor/Microsoft.Management.Configuration.Processor.csproj |
| [src-ConfigFlow] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerCLICore/Workflows/ConfigurationFlow.cpp |
| [src-Import] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerCLICore/Workflows/ImportExportFlow.cpp |
| [src-MultiQuery] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerCLICore/Workflows/MultiQueryFlow.cpp |
| [src-Install] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerCLICore/Workflows/InstallFlow.cpp |
| [src-Update] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerCLICore/Workflows/UpdateFlow.cpp |
| [src-ShellExec] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/AppInstallerCLICore/Workflows/ShellExecuteInstallerHandler.cpp |
| [src-PSInstallResult] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/PowerShell/Microsoft.WinGet.Client.Engine/PSObjects/PSInstallResult.cs |
| [src-WinGetClient] | https://github.com/microsoft/winget-cli/blob/v1.29.380/src/PowerShell/Microsoft.WinGet.Client/ModuleFiles/Microsoft.WinGet.Client.psd1 |
| [local] | 이 PC 에서 직접 돌린 읽기 전용 명령 (winget v1.29.380, pwsh 7.6.9) |

표기: 줄 번호(`L123`)는 위 태그 기준 소스 파일의 줄이다. 공식 문서에 없고 소스에서만 읽은 내용은 **(소스)** 로 표시했다.

## 1. `winget configure` (WinGet Configuration / DSC)

### 1.1 형식과 2026년 현재 상태

- 형식은 두 가지다.
  - **0.2 스키마**: `properties.resources[]` 아래에 `Microsoft.WinGet.DSC/WinGetPackage` 같은 PowerShell DSC 리소스를 적는다 [L-create]. 처리기가 PowerShell SDK(PowerShell 7 엔진)를 직접 품고 있어서, PC 에 설치된 pwsh 와 상관없이 돈다 **(소스)** [src-Processor]. 실행할 때 필요한 모듈을 PSGallery 에서 내려받는다 [L-config]. `Microsoft.WinGet.DSC` 모듈은 `CompatiblePSEditions = 'Core'`, `PowerShellVersion = '7.2'` 이고 `Microsoft.WinGet.Client` 모듈을 요구한다 [src-WinGetDSC].
  - **v3 스키마(dscv3 처리기)**: 최상위 `resources[]` 에 `type: Microsoft.WinGet/Package` 를 적는다. winget 1.11 이상이 필요하다. 처리기는 별도 패키지 `Microsoft.DesiredStateConfiguration` 이고, winget 이 알아서 설치한다 [L-create-v3]. 소스를 보면 Microsoft Store 제품 ID `9NVTPZWRC6KQ` 를 Store 설치 흐름으로 받는다 **(소스)** [src-ConfigFlow L76, L256–278].
- DSC v3 지원은 v1.11.400(2025-06-18) 릴리스 노트에 정식 기능으로 올라 있다 [rel-1.11.400]. `winget configure export` 로 새 파일을 만들면 dscv3 처리기 파일이 된다 **(소스)** [src-ConfigFlow L2248]. 마이크로소프트가 v3 쪽으로 옮겨 가는 중이다.
- v1.29.x 에서도 v3 `Microsoft.WinGet/Package` 리소스 버그가 계속 고쳐지고 있다. 예를 들어 `useLatest` 기본값이 문자열 `"false"` 로 나가던 문제, `installMode` 를 무시하던 문제가 v1.29.380 에서야 고쳐졌다 [rel-1.29.380].
- v3 에서는 PowerShell 기반(adapted) 리소스의 모듈을 자동으로 설치해 주지 않는다. `RunCommandOnSet` 리소스로 직접 설치해야 한다 [L-create-v3].
- [local] 이 PC 에서는 `dsc` 가 PATH 에 없고 `Microsoft.WinGet.*` 모듈도 설치돼 있지 않다. 즉 configure 를 처음 돌리는 순간 위 의존물이 추가로 설치된다.

### 1.2 멱등성: 이미 설치된 앱, 다른 버전이 설치된 앱

v3 `Microsoft.WinGet/Package` 의 속성은 [local] `winget dscv3 package --schema` 로 확인했다: `id`(필수), `source`, `version`, `useLatest`(기본 false), `_exist`, `matchOption`, `installMode`(기본 silent), `acceptAgreements`. **scope 속성은 없다.** 소스에 scope 지원은 TODO 로 남아 있다 [src-DscPackage L29–34].

동작 **(소스)** [src-DscPackage L274–360 `Test`, L403–460 `Set`]:

| 상황 | 결과 |
| --- | --- |
| 설치 안 됨 | 설치 |
| 설치됨, `version`·`useLatest` 둘 다 없음 | 원하는 상태로 본다. 아무것도 하지 않는다 |
| `version` 지정, 설치본과 같음 | 그대로 |
| `version` 지정, 설치본이 더 낮음 | 그 버전으로 업그레이드 |
| `version` 지정, 설치본이 더 높음 | `--uninstall-previous` 로 다시 설치(다운그레이드) |
| `useLatest: true`, 새 버전 있음 | 업그레이드 |
| `_exist: false` | 제거 |

0.2 `WinGetPackage` 도 규칙이 같다(`Ensure`, `Version`, `UseLatest`). 설치본이 더 높거나 버전을 알 수 없으면 제거한 뒤 다시 설치한다 [src-WinGetDSC L553–575].

### 1.3 관리자 권한과 UAC 프롬프트 수

- 0.2: 리소스에 `securityContext: elevated` 를 달면 **구성을 시작할 때 UAC 를 1번** 묻고, 승격 프로세스와 일반 프로세스를 하나씩 띄워 나눠 실행한다 [L-create].
- v3: 문서에는 "UAC 승인을 묻고 승격된 프로세스에서 리소스를 실행한다"고만 적혀 있다 [L-create-v3]. 소스를 보면 제한 토큰으로 실행될 때 두 처리기가 같은 dynamic factory 를 쓴다 **(소스)** [src-ConfigFlow L311–313]. 그래서 v3 도 1회일 가능성이 높지만, 실측하지는 않았다.
- 어느 앱에 `elevated` 가 필요한지는 사람이 적어야 한다. 매니페스트가 `ElevationRequirement: elevationRequired` 인 패키지, 서비스를 설치하는 패키지, machine scope 설치에 필요하다 [L-create-v3].
- `--accept-configuration-agreements` 를 주지 않으면 실행할 때마다 확인 프롬프트가 뜬다 [L-configure].

### 1.4 실패 동작과 결과 보고

- 단위 하나가 실패해도 나머지는 계속 진행한다. `dependsOn` 으로 걸린 단위만 건너뛴다. 끝난 뒤 실패 여부를 확인하는 것은 사용자 몫이라고 문서에 적혀 있다 [L-config].
- 결과는 콘솔에 단위별로 나온다. 전체가 실패하면 처리기의 결과 코드가 그대로 종료 코드가 된다 **(소스)** [src-ConfigFlow L2400–2406]. 적용 기록은 `winget configure list` 로 볼 수 있다 [L-configure].
- `winget configure test` 는 원하는 상태가 아니면 `S_FALSE`(종료 코드 1)를, test 자체가 실패하면 `0x8A15C00F` 를 돌려준다 **(소스)** [src-ConfigFlow L2427–2436], [rc].

### 1.5 사람이 직접 고치기 쉬운가

- 앱 하나에 6–9줄이 든다(`type`, `name`, `properties.id`, `properties.source`, `metadata.description`, 필요하면 `metadata.winget.securityContext`). `#` 주석은 쓸 수 있고, 순서는 상관없다 [L-create-v3].
- **재실행 비용**: `winget configure test` 기준으로 `Microsoft.WinGet/Package` 하나에 약 8–16초, dscv3 처리기 시작에 약 23초가 든다 [L-create-v3]. 앱이 60개면 test 만 8–16분이다.

### 1.6 PowerShell 7 에서

- `winget configure -f <파일> --accept-configuration-agreements` 를 pwsh 에서 그대로 쓴다.
- v3 의 `Microsoft.DSC.Transitional/PowerShellScript` 는 PC 에 설치된 pwsh 로 돈다. 그래서 PowerShell 패키지 리소스를 `dependsOn` 으로 먼저 걸어야 한다 [L-create-v3].

## 2. `winget export` JSON + `winget import`

### 2.1 형식

- 스키마 2.0 구조: `Sources[].SourceDetails{Name, Identifier, Argument, Type}` 아래에 `Packages[]{PackageIdentifier, Version?, Channel?, Scope?(user|machine), InitialOverrideArguments?, InitialCustomSwitches?}` 가 온다. 정의되지 않은 필드도 허용된다(`additionalProperties: true`) [schema-pkgs].
- v1.29 부터 `export` 가 처음 설치할 때 쓴 `--override`·`--custom` 인자를 저장하고, `import` 가 이를 다시 적용한다 [rel-1.29.380].
- `export` 는 `--include-versions` 를 주지 않으면 버전을 적지 않는다. 버전이 없으면 `import` 는 최신을 설치한다 [L-export].
- [local] 이 PC 에서 `winget export` 를 임시 폴더로 받아 봤다.
  - 패키지 91개(winget 90, msstore 1). 그중 25개는 VCRedist·.NET·WindowsAppRuntime 같은 런타임이다.
  - 원본에서 찾지 못한 앱 경고가 128줄 나왔다.
  - 모든 항목에 `PackageIdentifier` 만 있고 `Scope` 는 없다.
  - 들여쓰기는 탭이고, `CreationDate` 가 매번 바뀐다.

### 2.2 멱등성과 버전

`import` 는 각 패키지를 `winget install` 과 같은 "설치 또는 업그레이드" 흐름에 태운다 **(소스)** [src-Update L319–365]:

| 상황 | 결과 |
| --- | --- |
| 설치 안 됨 | 설치(파일에 `Version` 이 있으면 그 버전) |
| 설치됨, `--no-upgrade` | "이미 설치됨"으로 건너뜀 |
| 설치됨, 기본값 | **업그레이드 흐름으로 바뀜.** 새 버전이 없을 때만 "이미 설치됨"으로 건너뜀 |
| `Version` 지정, 설치본이 더 낮음 | 그 버전으로 업그레이드 |
| `Version` 지정, 설치본이 더 높음 | "적용할 업데이트 없음"으로 건너뜀. **다운그레이드하지 않는다** |
| `--ignore-versions` | 파일의 버전을 지우고 최신으로 진행 [src-Import L238–248] |

- pin 은 지켜진다 **(소스)** [src-Update L75, L350]. 다만 pin 은 PC 안에만 저장되는 상태다. JSON 에도 configure 파일에도 담기지 않고, `winget pin add` 로 따로 걸어야 한다 [L-pin].
- [local] 실제 예: 이 PC 의 `winget list --id Git.Git -e` 결과는 설치 2.47.0.2, 사용 가능 2.56.0.4 이다. 이 상태에서 기본값으로 `import` 를 다시 돌리면 Git 이 업그레이드된다.

### 2.3 관리자 권한과 UAC 프롬프트 수

- `import` 자체는 관리자를 요구하지 않는다. 권한은 설치 관리자마다 따로 결정된다.
  - 일반 권한 winget 은 `elevationRequired` 설치 관리자를 `runas` 로 실행한다 **(소스)** [src-ShellExec L33, L305]. 스스로 승격하는 설치 관리자도 각자 UAC 를 띄운다. 결국 **승격이 필요한 앱마다 UAC 가 1번씩** 뜬다.
  - 승격된 셸에서 돌리면 UAC 가 더 뜨지 않는다. 대신 `ElevationProhibited` 설치 관리자는 `0x8A150056` 으로 실패한다 **(소스)** [src-Install L681–686], [rc].
  - portable·msix·msstore 를 machine scope 로 설치하려면 winget 자체가 관리자로 돌아야 한다 **(소스)** [src-Install L473–483].
- `import` 한 번 안에서 "이 앱들만 승격"처럼 나눌 방법은 없다.

### 2.4 실패 동작과 결과 보고

- **찾기 단계**: 모든 패키지를 먼저 찾는다. 못 찾거나 여러 개가 걸려도 경고를 내고 나머지를 계속 찾는다. 하지만 끝에 하나라도 실패가 있으면 **전체를 `0x8A150067` 로 끝내고 아무것도 설치하지 않는다.** `--ignore-unavailable` 을 주면 그 패키지만 건너뛴다 **(소스)** [src-MultiQuery L124–145]. 버전을 고정한 항목이 원본에서 빠지면 이 단계에서 걸린다.
- 사용권 동의 프롬프트는 설치를 시작하기 전에 한꺼번에 묻는다 **(소스)** [src-Install L734].
- **설치 단계**: 하나가 실패해도 나머지를 계속 설치하고, 끝에 `0x8A150034`(가져온 패키지 하나 이상 설치 실패)를 돌려준다 **(소스)** [src-Install L784–853], [src-Import L352–371], [rc].
- 결과는 콘솔 텍스트와 로그 파일뿐이다. 어떤 앱이 실패했는지 기계가 읽을 수 있는 출력은 없다.

### 2.5 사람이 직접 고치기 쉬운가

- 앱 하나에 3줄이지만 `Sources[]` 아래에 중첩된다. JSON 이라 주석을 달 수 없다. 끝 쉼표 하나만 잘못 붙어도 파일 전체가 `0x8A150036` 으로 거부된다 [src-Import L203–226], [rc].
- `export` 로 다시 만들면 `CreationDate`·순서·들여쓰기가 바뀌어서 diff 에 잡음이 섞인다.

### 2.6 PowerShell 7 에서

```powershell
winget import -i apps.json --no-upgrade --accept-package-agreements --accept-source-agreements --disable-interactivity
```

## 3. `.psd1` 목록 + `winget install` 루프 직접 구현

### 3.1 형식 (예시)

```powershell
@{
    Apps = @(
        @{ Id = 'Git.Git' }
        @{ Id = 'Microsoft.PowerShell'; Elevated = $true }
        @{ Id = 'okibcn.nano' }                         # scoop 과 같은 빌드
        @{ Id = 'Example.Tool'; Version = '1.2.3' }     # 고정 이유를 여기에 적는다
    )
}
```

- `Import-PowerShellDataFile` 는 파일 안의 코드를 실행하지 않고 값만 읽는다 [L-psd1]. 기본 한도는 키 500개·AST 노드 5000개이고, `-SkipLimitCheck` 로 풀 수 있다 [L-psd1]. 앱 수십 개 규모면 한도 안쪽일 것으로 보이지만 실측하지는 않았다.
- 이 저장소의 `agent-accounts` 도 이미 `accounts.psd1` 을 같은 방식으로 쓴다.

### 3.2 멱등성과 버전: 루프가 정한다

- `winget install` 은 2.2 와 같은 흐름이다. 기본 동작은 업그레이드이고, `--no-upgrade` 를 주면 "없을 때만 설치"가 된다 **(소스)** [src-Update L330–343]. `winget install --help` 설명에도 "기본적으로 설치 상태를 확인하고 해당되면 업그레이드를 시도한다"고 나온다 [local].
- 루프가 성공으로 볼 종료 코드 [rc], **(소스)** [src-Update L156–195]:

| 코드 | 이름 | 뜻 |
| --- | --- | --- |
| `0` | — | 설치 또는 업그레이드 성공 |
| `0x8A150061` | `PACKAGE_ALREADY_INSTALLED` | `--no-upgrade` 일 때 이미 설치됨 |
| `0x8A15002B` | `UPDATE_NOT_APPLICABLE` | 새 버전 없음, 또는 지정 버전이 설치본보다 낮음 |
| `0x8A150068` | `PACKAGE_IS_PINNED` | pin 때문에 업그레이드 안 함 |
| `0x8A150109` | `INSTALL_REBOOT_REQUIRED_TO_FINISH` | 설치됨, 재부팅 필요 |

- [local] pwsh 7 에서 `$LASTEXITCODE` 는 Int32 이고, `0x8A150061` 같은 16진 리터럴도 Int32(음수)로 읽힌다. 그래서 `$LASTEXITCODE -eq 0x8A150061` 처럼 바로 비교할 수 있다.
- [local] 설치 여부만 미리 확인: `winget list --id <Id> -e` 는 설치돼 있으면 `0`, 없으면 `0x8A150014` 를 돌려준다. 앱이 많으면 `winget export` 를 임시 파일로 한 번 받아서 설치된 ID 집합을 만드는 편이 빠르다.
- 다운그레이드는 `winget install` 이 하지 않는다(2.2). 필요하면 루프가 직접 처리해야 한다.
- 버전을 고정한 앱은 루프가 `winget pin add --id <Id> --version <범위>` 도 함께 걸 수 있다. 그러면 `winget upgrade --all` 을 돌려도 범위를 벗어나지 않는다 [L-pin].

### 3.3 관리자 권한과 UAC 프롬프트 수

- 루프는 앱을 두 묶음으로 나눌 수 있다.
  - `Elevated = $true` 인 앱: 승격된 pwsh 자식 프로세스 하나에서 설치한다(UAC 1회).
  - 나머지: 일반 권한으로 설치한다(`ElevationProhibited` 실패를 피한다).
- 어느 앱이 승격을 필요로 하는지는 configure 와 마찬가지로 사람이 목록에 적는다. 이 부분은 #42(관리자 권한 처리)와 겹친다.

### 3.4 실패 동작과 결과 보고

- 앱별로 결과를 모아 두고 다음 앱으로 넘어간다. 끝에 표(Id, 결과, 종료 코드)를 출력하고, 실패가 하나라도 있으면 0이 아닌 코드로 끝낸다. 형식은 우리가 정한다.
- 객체로 결과를 받고 싶다면 `Microsoft.WinGet.Client` 모듈(PSGallery, Windows PowerShell 5.1·PowerShell 7 모두 지원)의 `Install-WinGetPackage` 가 `Status`·`InstallerErrorCode`·`RebootRequired` 를 돌려준다 [src-PSInstallResult], [src-WinGetClient]. 다만 PSGallery 모듈이 의존성으로 하나 늘어난다.

### 3.5 사람이 직접 고치기 쉬운가

- 앱 하나가 한 줄이다. 주석을 달 수 있고, 섹션으로 묶을 수 있고, 순서도 자유다. diff 한 줄이 곧 앱 하나다.
- 대신 스키마 검증(키 오타, Id 중복, 알 수 없는 키)은 직접 만들어야 한다.

### 3.6 PowerShell 7 에서

- winget.exe 를 그대로 호출한다. [local] 출력은 한국어로 지역화돼 나오므로 텍스트를 파싱하면 안 되고, 종료 코드만 본다.

## 비교 표

| 기준 | `winget configure` (DSC) | `winget import` (JSON) | `.psd1` + install 루프 |
| --- | --- | --- | --- |
| 이미 설치된 앱 | 버전 조건이 없으면 건드리지 않음 | 기본: 업그레이드 시도. `--no-upgrade` 면 건너뜀 | 루프가 정함(`--no-upgrade` 로 건너뛰기 가능) |
| 다른 버전이 설치된 앱 | `version` 을 적으면 낮을 때 업그레이드, 높을 때 제거 후 재설치(다운그레이드) | `Version` 을 적으면 낮을 때 업그레이드, 높을 때 건너뜀(다운그레이드 없음) | install 과 같음. 다운그레이드는 직접 |
| 버전 고정 | `version` / `useLatest` | `Version` (`export --include-versions`) | 목록의 `Version` + 필요하면 `winget pin` |
| scope 지정 | 불가(속성 없음) | `Scope` user/machine | `--scope` 를 포함한 install 옵션 전부 |
| 관리자·UAC | `elevated` 단위가 있으면 시작할 때 1회(0.2 문서 기준) | 일반 권한: 승격이 필요한 앱마다 1회. 승격 셸: 0회지만 `ElevationProhibited` 앱은 실패 | 묶음을 나누면 1회(직접 구현) |
| 앱 하나가 실패하면 | 나머지 계속, `dependsOn` 걸린 것만 건너뜀 | 찾기 단계 실패는 전체 중단(`--ignore-unavailable` 없을 때). 설치 단계는 계속하고 끝에 `0x8A150034` | 우리가 정함. 계속하고 끝에 모아서 보고 가능 |
| 결과 보고 | 콘솔 단위별 출력, `configure list` 기록, `configure test` | 콘솔 텍스트와 로그 | 직접 만든 표와 종료 코드 |
| 고치기·diff | 앱당 YAML 6–9줄, 주석 가능 | 앱당 JSON 3줄, 주석 불가, 다시 export 하면 잡음 | 앱당 1줄, 주석 가능 |
| 재실행 속도 | Package 하나 test 8–16초 + 처리기 시작 23초 | 앱마다 찾기 + 설치 흐름 | 설치 목록 1번 조회 후 빠진 앱만 설치 |
| 추가 의존 | 0.2: PSGallery 모듈. v3: Store 의 DSC v3 패키지 | 없음 | 없음(모듈을 쓰면 PSGallery) |
| PowerShell 7 | 0.2 는 내장 PS7 엔진, v3 스크립트 리소스는 설치된 pwsh 필요 | 일반 명령 호출 | 일반 명령 호출, 종료 코드는 Int32 로 비교 |
| 2026-11 상태 | v3 정식(1.11.400~), 1.29 에서도 v3 Package 리소스 버그 수정 중 | 안정. 1.29 에서 override/custom 보존 추가 | winget CLI 의 안정 기능만 씀 |

## 추천 (#44 판단용)

1. **1순위: `.psd1` 목록 + `winget install` 루프.**
   - 목록을 사람이 고치기 가장 쉽고(한 줄, 주석), 도구 제약(winget·pwsh·git)을 깨지 않는다.
   - UAC 를 나누는 방법, 실패를 모아 보고하는 방법, 이미 설치된 앱을 다루는 방법을 우리가 정할 수 있다.
   - 루프는 셋업 안의 한 함수로 끝난다. 이 저장소에는 이미 같은 방식(`accounts.psd1`)이 있다.
2. 루프 동작 초안(결정은 #44 에서):
   - 기본은 "없으면 설치, 있으면 그대로"(`--no-upgrade`). 업그레이드는 셋업과 분리해 `winget upgrade` 로 따로 한다. 그래야 셋업을 다시 돌려도 앱 버전이 바뀌지 않는다.
   - 버전 고정이 필요한 앱만 `Version` 을 적고 `winget pin` 도 함께 건다.
   - 위 표의 종료 코드를 성공으로 본다. 끝에 앱별 결과 표를 출력하고, 실패가 있으면 0이 아닌 코드로 끝낸다.
   - 승격이 필요한 앱은 묶어서 승격 자식 프로세스 하나로 설치한다(#42 와 맞춘다).
3. `winget configure` 를 쓸 만한 곳: Windows 설정(레지스트리)을 셋업에 넣기로 하면(지도의 Not yet specified), 그 부분만 v3 `Microsoft.Windows/Registry` 로 쓰는 것을 검토할 수 있다. 네이티브 리소스라 모듈이 필요 없고 리소스 하나에 약 3초다 [L-create-v3]. 앱 목록은 루프로 둔다.
4. `winget export` 는 **선언** 형식이 아니라 #40(목록 수집)의 출발 자료로 쓴다. 이 PC 기준으로 91개 중 25개가 런타임이어서 골라내는 작업이 필요하다.

## 다른 티켓에 주는 사실

- **#42 (부트스트랩·관리자 권한)**
  - 셋업 전체를 관리자로 돌리면 UAC 는 줄지만 `ElevationProhibited` 앱이 `0x8A150056` 으로 실패한다.
  - 일반 권한으로 돌리면 승격이 필요한 앱마다 UAC 가 뜬다.
  - portable·msix·msstore 를 machine scope 로 설치하려면 winget 자체가 관리자여야 한다.
  - 요구 버전: `winget configure` 는 1.6.2631 이상, v3 는 1.11 이상 [L-configure], [L-create-v3]. 새 Windows 에 들어 있는 winget 버전은 확인하지 않았다.
- **#46 (셋업 검증)**
  - `winget configure test` 는 원하는 상태가 아니면 종료 코드 1(`S_FALSE`)을 준다.
  - 루프 방식에서는 `winget list --id <Id> -e` 의 종료 코드(`0` / `0x8A150014`)로 "test 모드"를 만들 수 있다.
- **#40 / #43 (목록 수집·선별)**
  - `winget export` 결과에는 런타임·프레임워크가 섞여 있다(이 PC: 91개 중 25개).
  - 원본에 없는 앱은 경고로만 나오고 목록에서 빠진다(이 PC: 128줄).
  - `Scope` 와 버전은 기본으로 적히지 않는다.
- **지도 #36 의 가정**
  - "도구는 winget·pwsh·git 만"이라는 조건은 configure 를 고르면 깨진다. 0.2 는 PSGallery 모듈을, v3 는 Store 의 DSC v3 패키지를 자동으로 받아 오기 때문이다.
  - "멱등"을 "앱이 설치돼 있음"으로 볼지 "버전까지 같음"으로 볼지 정해야 한다. winget 기본값(install·import)은 재실행할 때 업그레이드를 한다. 예: 이 PC 의 Git 은 2.47 이 설치돼 있고 2.56 을 받을 수 있다.

## 확인하지 못한 것

- v3 configure 의 실제 UAC 횟수(이 PC 에서 구성을 적용하지 않았다).
- `winget configure` / `winget import` 를 실제로 돌렸을 때의 출력. 위 실패 동작은 문서와 소스로만 판단했다.
- `.psd1` 앱 목록이 `Import-PowerShellDataFile` 한도(키 500·AST 노드 5000)에 얼마나 가까운지.
- 새로 설치한 Windows 11 이미지에 들어 있는 winget(App Installer) 버전.
