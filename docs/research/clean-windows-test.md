# 깨끗한 Windows 에서 셋업 검증하는 방법: Windows Sandbox·Hyper-V

이슈: hdmun/anything#39 (맵 #36) · 조사일 2026-11-07 · 이 PC 에서는 읽기 전용 확인만 했다(Sandbox 실행·VM 생성은 하지 않음). 그래서 아래 시간은 모두 **추정**이다.

용어는 `pc-setup/CONTEXT.md` 를 따른다: **선언**(PC 가 있어야 할 상태), **셋업**(선언에 맞추는 멱등 실행), **부트스트랩**(빈 Windows 에서 셋업 첫 실행까지).

## 결론 요약

- **평소 검증은 Windows Sandbox 로 한다.** 이 PC 에 이미 켜져 있다. 창을 닫으면 처음 상태로 돌아가므로 되돌리기 비용이 없다.
- **Sandbox 에는 winget 이 없다.** Microsoft Store 도 없다. 그래서 부트스트랩 맨 앞에 "winget 보장" 단계가 있어야 한다. 실제 새 PC 도 첫 로그인 직후에는 winget 이 아직 등록되지 않았거나 낡은 버전일 수 있다. 같은 단계 하나로 두 경우를 함께 처리한다.
- **"Sandbox 는 재부팅 불가"는 옛날 이야기다.** Windows 11 22H2 부터 Sandbox 안에서 재시작해도 데이터가 남는다. 다만 재시작 뒤 `LogonCommand` 가 다시 도는지는 문서에 없다(미확인).
- **Sandbox 는 "갓 설치한 PC"와 다른 점이 있다.** 사용자가 관리자 `WDAGUtilityAccount` 이고, Store·Terminal·Notepad 같은 기본 Store 앱이 없고, OS 빌드가 호스트와 같다. 그래서 UAC 흐름·msstore 앱·OOBE 직후 상태는 확인하지 못한다.
- **Hyper-V VM 은 큰 변경 뒤 가끔 하는 최종 확인용이다.** 이미지 준비에 1~2시간(1회)이 들지만, 체크포인트 복원으로 매번 같은 "OOBE 직후" 상태에서 시작할 수 있다. 실제 UAC·Store·재부팅까지 확인된다.
- 1회 검증 시간은 두 방법 모두 **부트스트랩·셋업의 다운로드 시간이 대부분**이다(앱 30개 가정 20~40분, 추정). 기동·되돌리기 차이는 몇 분 수준이다.

## 0. 이 PC 확인 (읽기 전용)

| 항목 | 결과 | 확인 방법 |
|---|---|---|
| OS | Windows 11 Pro 25H2, 빌드 26200 | `Win32_OperatingSystem`, 레지스트리 `EditionID=Professional` |
| Windows Sandbox | 켜져 있음 | `C:\Windows\System32\WindowsSandbox.exe` 있음, `CmService` 실행 중, Appx `MicrosoftWindows.WindowsSandbox` 0.8.107.0 |
| `wsb` CLI | 있음 | `wsb --help` (start·list·exec·share·stop·connect·ip) |
| Hyper-V | 켜져 있음 | `vmms` 서비스 실행 중, `HypervisorPresent=True`, `C:\Program Files\Hyper-V\VMCreate.exe`(빠른 생성) 있음 |
| CPU | 6코어 12스레드, 펌웨어 가상화 켜짐 | `Win32_Processor.VirtualizationFirmwareEnabled=True` |
| 메모리·디스크 | RAM 약 32GB, C: 여유 약 188GB | `Win32_ComputerSystem`, `Get-PSDrive C` |
| 호스트 winget | v1.29.380 | `winget --version` |

두 방법 모두 기능을 새로 켤 필요가 없다.

## 1. Windows Sandbox

### 1.1 Sandbox 안의 Windows 는 어떤 상태인가

- **호스트와 같은 빌드다.** Sandbox 는 따로 Windows 이미지를 받지 않는다. 호스트에 설치된 Windows 파일을 공유해서 부팅한다("Dynamic Base Image"). 이 PC 에서는 25H2 26200 이 된다. 실제 새 PC 를 다른 빌드의 ISO 로 설치하면 그 차이는 Sandbox 에서 보이지 않는다. ([Architecture](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-architecture))
- **매번 새것이다.** "Every time Windows Sandbox runs, it's as clean as a brand-new installation of Windows." 닫으면 설치한 앱·파일·상태가 모두 지워진다. ([Overview](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview))
- **Windows PowerShell 5.1 이 있고 PowerShell 7 은 없다.** Microsoft 예제가 `LogonCommand` 에서 `powershell.exe` 를 그대로 부른다. 부트스트랩이 5.1 에서 시작하는 조건을 그대로 재현한다. ([Sample configuration](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-sample-configuration), 예제 3)
- **winget·Microsoft Store 가 없다.** "Windows Sandbox does not include WinGet, nor the Microsoft Store app". ([WinGet 문서](https://learn.microsoft.com/en-us/windows/package-manager/winget/), "Install WinGet on Windows Sandbox")
- **기본 Store 앱도 없다.** 24H2 부터 Calculator·Photos·Notepad·Terminal 이 Sandbox 안에 없다. ([Install](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-install))
- **사용자는 관리자 `WDAGUtilityAccount` 다.** "The default user of Sandbox is `WDAGUtilityAccount`", "The container user account should be an administrator account." ([.wsb 설정](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file))
- **실행 정책은 Restricted 다(추정).** 어느 범위에도 실행 정책이 없으면 Windows 클라이언트는 Restricted 이고 `.ps1` 을 실행하지 않는다. 그래서 스크립트는 `powershell.exe -ExecutionPolicy Bypass -File ...` 로 부른다. 같은 문서에 로그온 스크립트가 데스크톱 준비 전에 돌면 zone 검사가 실패할 수 있고, Bypass 는 그 검사를 건너뛴다고 나온다. ([about_Execution_Policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies))
- **메모리 기본 상한은 4GB 다.** `<MemoryInMB>` 로 늘린다(최소 2048). 이 PC(32GB)에서는 8192 정도가 무난하다. ([.wsb 설정](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file))
- **한 번에 하나만 띄울 수 있다.** "Windows Sandbox currently doesn't allow multiple instances to run simultaneously." ([Overview](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview))

### 1.2 winget 넣기

방법 두 가지가 1차 출처에 있다.

**(가) Microsoft 문서 방법: `Repair-WinGetPackageManager`.** Sandbox 의 Windows PowerShell 에서 실행한다. ([WinGet 문서](https://learn.microsoft.com/en-us/windows/package-manager/winget/))

```powershell
$progressPreference = 'silentlyContinue'
Install-PackageProvider -Name NuGet -Force | Out-Null
Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
Repair-WinGetPackageManager -AllUsers
```

- `-AllUsers` 는 관리자 권한이 필요하다. Sandbox 사용자는 관리자라 그대로 된다. ([Repair-WinGetPackageManager](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Help/Microsoft.WinGet.Client/Repair-WinGetPackageManager.md))
- 이 cmdlet 은 GitHub 릴리스 정보를 조회한다. 인증 없이 자주 부르면 GitHub 횟수 제한에 걸릴 수 있다. `GH_TOKEN` 이나 `GITHUB_TOKEN` 환경 변수가 있으면 그것을 쓴다. Sandbox 를 하루에 여러 번 돌리면 걸릴 수 있다. (같은 문서, Notes)
- 매번 PSGallery·GitHub 에서 내려받는다. winget 최신 릴리스 v1.29.380(2026-09-21) 기준으로 `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle` 약 207MB, `DesktopAppInstaller_Dependencies.zip` 약 93MB 다(`gh api repos/microsoft/winget-cli/releases/latest`).

**(나) Microsoft winget-pkgs 의 `SandboxTest.ps1` 방법: 호스트 캐시 + `Add-AppxPackage`.** winget 패키지 검증용으로 Microsoft 가 직접 쓰는 스크립트다. ([Tools/SandboxTest.ps1](https://github.com/microsoft/winget-pkgs/blob/master/Tools/SandboxTest.ps1))

- 호스트에서 winget-cli 릴리스의 msixbundle 과 `DesktopAppInstaller_Dependencies.zip` 을 받는다. SHA256 이 맞으면 다음 실행에서 다시 받지 않는다.
- 그 폴더를 Sandbox 에 매핑하고, 안에서 의존성 `.appx` 를 먼저 `Add-AppxPackage` 한 뒤 msixbundle 을 `Add-AppxPackage` 한다.
- 실패하면 (가)의 `Repair-WinGetPackageManager` 로 넘어간다.
- `.wsb` 는 `WindowsSandbox` 명령으로 연다. `wsb` CLI 는 이미 떠 있는 Sandbox 를 끄는 데만 쓴다.

**실제 새 PC 의 winget 상태.** "WinGet will not be available until you have logged into Windows as a user for the first time". 첫 로그인 뒤 Store 가 비동기로 등록하므로, 바로 쓰려면 `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe` 로 등록을 요청한다. ([WinGet 문서](https://learn.microsoft.com/en-us/windows/package-manager/winget/)) 설치 매체에 든 winget 이 너무 낡아서(1.2) 원본 CDN 이 없어져 아무것도 설치하지 못한 사례도 있다. ([winget-cli#4187](https://github.com/microsoft/winget-cli/issues/4187))

**부트스트랩에 주는 시사점.** "winget 보장" 단계를 하나 둔다.

1. `winget` 이 있고 버전이 충분하면 넘어간다.
2. 없으면 `-RegisterByFamilyName` 등록을 시도한다. 실제 새 PC 는 대개 여기서 해결된다. Sandbox 에는 패키지가 없어서 실패한다(예상).
3. 그래도 없거나 낡았으면 `Repair-WinGetPackageManager` 를 쓴다. Sandbox 는 여기서 해결된다.

이렇게 하면 Sandbox 검증이 실제 새 PC 와 같은 코드 경로를 지난다. 시간을 줄이려면 (나)처럼 캐시에서 미리 설치하는 옵션을 검증 스크립트에 둘 수 있다. 다만 그때는 2·3단계를 시험하지 않는다.

**msstore 원천.** Store 가 없으므로 winget 의 `msstore` 원천 앱은 Sandbox 에서 설치를 확인할 수 없다고 본다(추정). 비대화식 실행에서는 `--accept-source-agreements --accept-package-agreements` 를 붙여야 원천 약관 프롬프트에 막히지 않는다.

### 1.3 저장소 넣기: `MappedFolders`

출처: [.wsb 설정](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file)

- `HostFolder` 는 호스트에 **이미 있어야** 한다. 없으면 Sandbox 가 시작되지 않는다. 상대 경로는 안 된다. 23H2 부터 경로에 환경 변수를 쓸 수 있다. 그래서 `%USERPROFILE%\scripts` 처럼 쓰면 사용자 이름을 `.wsb` 에 적지 않고 저장소에 넣을 수 있다.
- `SandboxFolder` 를 비우면 Sandbox 사용자의 바탕화면에 매핑된다.
- 폴더 매핑은 `LogonCommand` 보다 **먼저** 끝난다.
- 쓰기 가능한 매핑 폴더에서 바꾼 내용은 Sandbox 를 닫아도 **호스트에 남는다.** 그래서 저장소는 `ReadOnly=true` 로 넣고, 로그·결과용 폴더만 따로 쓰기 가능으로 넣는다.

저장소를 Sandbox 안의 `~\scripts` 로 가져오는 길은 두 가지다.

1. **실제 부트스트랩 경로.** GitHub 에서 받는다(`irm <raw URL> | iex` 나 `git clone`). push 된 브랜치만 시험할 수 있다.
2. **로컬 변경 시험.** 매핑한 읽기 전용 저장소(예: `C:\src\scripts`)를 출처로 `git clone C:\src\scripts ~\scripts` 한다. push 하지 않은 커밋도 시험할 수 있다. 주의: Git 2.45.1 등은 CVE-2024-32004 대응으로 "ownership checks ... are now extended to cover cloning local repositories". 매핑 폴더의 소유자가 Sandbox 사용자와 달라 clone 이 거부되면 `safe.directory` 설정이 필요하다(미확인). ([Git 2.45.1 릴리스 노트](https://code.googlesource.com/git/+/HEAD/Documentation/RelNotes/2.45.1.adoc))

즉 부트스트랩은 **저장소 출처(URL 또는 로컬 경로)와 브랜치를 인자로 받을 수 있어야** 검증하기 쉽다.

### 1.4 자동 실행: `LogonCommand`

- 명령 **하나**를 로그온 직후 컨테이너 사용자로 실행한다. 여러 단계는 매핑한 폴더의 스크립트로 넣으라고 문서가 권한다. ([.wsb 설정](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file))
- `.wsb` 파일을 더블클릭하거나 명령줄에서 파일 이름을 실행하면 그 설정으로 뜬다. (같은 문서)

예시 (`pc-setup` 검증용, 경로는 예시):

```xml
<Configuration>
  <MemoryInMB>8192</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>%USERPROFILE%\scripts</HostFolder>
      <SandboxFolder>C:\src\scripts</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>%USERPROFILE%\pc-setup-test-out</HostFolder>
      <SandboxFolder>C:\out</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -NoExit -File C:\src\scripts\pc-setup\test\sandbox-run.ps1</Command>
  </LogonCommand>
</Configuration>
```

`sandbox-run.ps1`(구현 이슈에서 만들 것)이 할 일의 윤곽:

1. `Start-Transcript C:\out\run.log`
2. 부트스트랩 실행 (저장소 출처 = `C:\src\scripts`)
3. 셋업을 한 번 더 실행하고 "바뀐 것 0개"인지 확인 (멱등)
4. 결과(단계별 성공·실패, 걸린 시간)를 `C:\out\result.json` 에 쓴다. 호스트는 이 파일이 생기기를 기다린다.

**`wsb` CLI (24H2+)로 띄울 때 주의.** ([Command line](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-cli))

- `wsb start --config "<Configuration>...</Configuration>"` 는 파일 경로가 아니라 XML 문자열을 받고 Sandbox ID 를 돌려준다.
- `wsb exec` 는 종료 코드만 돌려준다: "there is no way to retrieve the output of a command run in Sandbox". 그래서 결과는 매핑 폴더로 받아야 한다.
- `wsb exec --run-as ExistingLogin` 은 로그인된 세션이 있어야 한다. 그 전에 `wsb connect` 로 원격 데스크톱 세션을 열어야 한다.
- `wsb start` 로만 띄우면 `wsb connect` 전까지 로그온이 없어서 `LogonCommand` 가 돌지 않는다는 2차 출처가 있다([LOLBAS wsb.exe](https://lolbas-project.github.io/lolbas/OtherMSBinaries/Wsb/), 미확인). 가장 단순한 방법은 Microsoft `SandboxTest.ps1` 처럼 `.wsb` 파일을 여는 것이다.

### 1.5 제약 정리

| 제약 | 내용 | 셋업 검증에 주는 영향 |
|---|---|---|
| 닫으면 삭제 | 쓰기 가능한 매핑 폴더만 남는다 | 결과는 매핑 폴더로 받는다 |
| 재부팅 | 22H2 부터 Sandbox 안 재시작에도 데이터 유지 ([Overview](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview)). 재시작 뒤 `LogonCommand` 재실행·매핑 유지는 미확인 | 셋업이 재부팅을 요구하면 직접 한 번 확인해야 한다 |
| winget·Store 없음 | 1.2 참고 | winget 보장 단계를 시험할 수 있다(장점). msstore 앱은 확인 불가 |
| 기본 Store 앱 없음 (24H2+) | Terminal·Notepad 없음 | Windows Terminal 설정 파일 대상 폴더는 winget 으로 Terminal 을 설치한 뒤에야 생긴다(추정). #45 의 설정 파일 연결 순서를 시험하는 데는 오히려 좋다 |
| 사용자가 관리자 | `WDAGUtilityAccount` | UAC 승격 흐름(#42)은 실제와 다르게 보일 수 있다(Sandbox 안 UAC 동작은 문서에 없음, 미확인). 관리자 권한 없이 symlink 를 만드는 Developer Mode 경로(#38)도 실제와 같게 시험되지 않는다(추정) |
| 사용자 이름이 다름 | `C:\Users\WDAGUtilityAccount` | 경로를 하드코딩하면 바로 드러난다(장점) |
| MSA·OneDrive 없음 | 로그인 계정이 없다 | 문서 폴더 OneDrive 리디렉션(#38) 상황은 재현할 수 없다 |
| OS 빌드 고정 | 호스트와 같은 빌드 | 다른 빌드는 시험할 수 없다 |
| 캐시 없음 | 매번 전부 내려받는다 | 검증 시간 대부분이 다운로드다 |
| 하나만 실행 | 동시 실행 불가 | 검증을 병렬로 돌릴 수 없다 |

## 2. Hyper-V VM

### 2.1 만들기

- Windows 11 VM 요건: 2세대, Secure Boot·가상 TPM 켜기, 메모리 4GB 이상, 디스크 64GB 이상, 가상 CPU 2개 이상. ([Windows 11 requirements](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements), "Virtual machine support")
- 만드는 방법: Hyper-V 관리자의 새 VM 마법사나 `New-VM -Generation 2 -NewVHDPath ... -NewVHDSizeBytes ...`. 관리자나 Hyper-V Administrators 그룹이어야 한다. ([Create a virtual machine](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/create-a-virtual-machine-in-hyper-v))
- **빠른 생성(Quick Create)** 은 갤러리 이미지나 로컬 ISO 로 VM 을 만든다. 이 PC 에도 `VMCreate.exe` 가 있다. 이를 따로 설명하는 Microsoft Learn 문서는 지금 찾지 못했다(옛 주소는 일반 VM 생성 문서로 넘어간다).
- **Microsoft 가 주던 "Windows 11 개발 환경" VM 은 더 이상 받을 수 없다.** 옛 다운로드 주소 `developer.microsoft.com/.../virtual-machines/` 는 2026-11-07 확인 시 VM 이야기가 없는 Learn 개발 도구 페이지로 301 리디렉션된다. 2025-04 에 사용자들이 "no longer published" 라고 보고했다. ([Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/2259075/windows-developer-vm-or-images-where-are-they-now)) 그래서 이미지는 직접 받은 Windows 11 ISO 로 만든다.

### 2.2 이미지 준비 비용 (1회)

1. Windows 11 ISO 받기 (수 GB)
2. VM 만들고 설치 + OOBE
3. (선택) Windows Update 로 최신화
4. 이 상태에서 체크포인트 `clean` 만들기

- OOBE 계정: Insider 빌드 26220.6772(2025-10) 공지에서 Microsoft 는 OOBE 의 로컬 계정 생성 방법들을 없앤다고 했다: "Users will need to complete OOBE with internet and a Microsoft account". ([Windows Insider Blog](https://blogs.windows.com/windows-insider/2025/10/06/announcing-windows-11-insider-preview-build-26220-6772-dev-channel/)) 일반 배포판에서 어디까지 적용됐는지는 미확인이다. 시험 VM 에도 Microsoft 계정과 인터넷이 필요하다고 보고 준비한다.
- 정품 인증·라이선스는 이 문서 범위 밖이다.
- 예상 시간: 다운로드·설치·OOBE·업데이트를 합쳐 **1~2시간**(추정, 네트워크 속도에 좌우).

### 2.3 체크포인트로 되돌리기

출처: [Using checkpoints](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/checkpoints)

- **기본은 프로덕션 체크포인트**다. VSS 로 디스크만 저장하고 메모리는 저장하지 않는다. 적용하면 VM 이 꺼진 상태가 된다. 그래서 매번 부팅·로그인이 필요하다.
- **표준 체크포인트**는 메모리까지 저장한다. 적용하면 찍은 순간의 실행 상태로 돌아간다. 로그인한 바탕화면에서 찍어 두면 부팅을 건너뛴다. `Set-VM -Name <VM> -CheckpointType Standard`.
- 명령: `Checkpoint-VM -Name <VM> -SnapshotName clean`, `Restore-VMCheckpoint -Name clean -VMName <VM> -Confirm:$false`.
- 체크포인트는 VHDX 옆에 `.avhdx` 로 쌓인다. 지울 때는 `Remove-VMCheckpoint` 를 쓴다(`.avhdx` 를 직접 지우지 않는다).
- "이미 셋업한 PC" 도 체크포인트로 둘 수 있다. 셋업 1회 뒤 `after-setup` 을 찍어 두면, 다음 버전의 셋업을 그 위에서 돌려 멱등·업그레이드를 시험할 수 있다.

### 2.4 호스트에서 자동으로 돌리기: PowerShell Direct

출처: [PowerShell Direct](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell-direct)

- 네트워크 설정과 관계없이 호스트에서 VM 안의 PowerShell 을 실행한다. 호스트는 Hyper-V 관리자 권한, VM 은 사용자 자격 증명이 필요하다. VM 이 켜져 있고 사용자 프로필이 하나 이상 있어야 한다.
- `Invoke-Command -VMName <VM> -ScriptBlock { ... }` 는 **출력을 호스트로 돌려준다.** Sandbox 의 `wsb exec` 보다 결과 받기가 쉽다.
- `New-PSSession -VMName` + `Copy-Item -ToSession` 으로 저장소를 넣고, `Copy-Item -FromSession` 으로 로그를 꺼낸다.
- Microsoft 계정으로 만든 VM 사용자로 PowerShell Direct 인증이 되는지는 미확인이다. 안 되면 OOBE 뒤 로컬 관리자 계정을 하나 더 만들어 둔다.

### 2.5 Sandbox 로는 안 되고 VM 으로 되는 것

- OOBE 직후의 실제 winget 상태(등록 타이밍, ISO 에 든 App Installer 버전)
- 일반 사용자 계정의 UAC 승격 흐름
- Store 와 `msstore` 원천 앱
- 재부팅이 필요한 단계와 재부팅 뒤 이어서 실행
- 원하는 Windows 빌드 고정(ISO 로 결정)

## 3. 비교

| 항목 | Windows Sandbox | Hyper-V VM |
|---|---|---|
| 준비 (1회) | 없음. 이 PC 에 이미 켜져 있다 | ISO·설치·OOBE·업데이트·체크포인트: 1~2시간 (추정) |
| 깨끗한 상태로 되돌리기 | 창 닫기 (자동) | `Restore-VMCheckpoint`: 1분 안팎 (추정) |
| 기동 | 수 초 ("a few seconds", 문서) | 표준 체크포인트 수십 초, 프로덕션 체크포인트는 부팅 포함 1~3분 (추정) |
| winget | 없음. 설치 필요(약 300MB) | 있음. 단 첫 로그인 후 비동기 등록, ISO 시점 버전 |
| Store·msstore | 없음 | 있음 |
| 사용자·UAC | `WDAGUtilityAccount`(관리자) | 실제 PC 와 같음 |
| 재부팅 | 22H2+ 데이터 유지, `LogonCommand` 재실행 미확인 | 됨 |
| OS 빌드 | 호스트와 같음 | ISO 로 고름 |
| 저장소 넣기 | `MappedFolders` (읽기 전용) | PowerShell Direct `Copy-Item -ToSession` 또는 GitHub clone |
| 자동 실행 | `LogonCommand` | `Invoke-Command -VMName` |
| 결과 받기 | 쓰기 가능한 매핑 폴더 (`wsb exec` 는 출력 없음) | `Invoke-Command` 출력, `Copy-Item -FromSession` |
| 디스크 | 기본 이미지 약 500MB + 세션 동안 사용량 | VHDX 64GB 이상 + 체크포인트 `.avhdx` |
| **1회 검증 시간** | 기동 1분 미만 + winget 1~3분 + 부트스트랩·셋업 2회(1회는 멱등 확인) | 복원·부팅 1~3분 + 부트스트랩·셋업 2회 |
| 앱 30개 가정 합계 (추정) | **약 20~40분** | **약 20~40분** (이미지 준비 별도) |

- 1회 검증 시간의 대부분은 앱 다운로드·설치다. 앱 수(#43)에 거의 비례한다. 두 번째 셋업 실행(멱등 확인)은 설치할 것이 없어서 짧다(`winget list` 조회 위주, 수 분 추정).
- 위 시간은 실측이 아니다. #46 에서 첫 Sandbox 실행 때 단계별 시간을 `result.json` 에 남겨 기준값으로 쓰는 것을 권한다.

## 4. 권장

1. **평소 검증은 Sandbox 로 한다.** `.wsb` 와 `sandbox-run.ps1` 을 `pc-setup/` 아래에 두고(구현 이슈), 부트스트랩(로컬 출처) → 셋업 → 셋업 재실행(멱등) → `result.json` 을 자동으로 돌린다.
2. **큰 변경 뒤나 실제 새 PC 에 쓰기 전에 Hyper-V VM 으로 한 번 확인한다.** OOBE 직후 체크포인트에서 실제 부트스트랩 경로(GitHub raw URL)를 돌려 winget 등록, UAC, Store 앱, 재부팅을 본다.
3. **부트스트랩 설계(#42)에 넣을 것**
   - "winget 보장" 단계 (1.2 의 1→2→3)
   - 저장소 출처(URL·로컬 경로)와 브랜치 인자
   - 로그·결과를 지정한 폴더에 쓰는 옵션
   - 비대화식 실행: `--accept-source-agreements --accept-package-agreements --disable-interactivity`
   - `.ps1` 은 `-ExecutionPolicy Bypass` 로 실행 (새 Windows 의 기본 실행 정책이 Restricted)

## 미확인 / 후속

- Sandbox 안에서 UAC 승격 프롬프트가 뜨는지 (`whoami /groups` 의 Mandatory Label 로 확인 가능)
- Sandbox 안 재시작 뒤 `LogonCommand` 재실행과 매핑 폴더 유지 여부
- `wsb start --config` 로 띄웠을 때 `wsb connect` 없이 `LogonCommand` 가 도는지
- 읽기 전용 매핑 폴더에서 `git clone` 할 때 소유자 검사(`safe.directory`)에 걸리는지
- 일반 배포판 Windows 11 OOBE 에서 로컬 계정을 만들 수 있는지, Microsoft 계정 VM 사용자로 PowerShell Direct 가 되는지
- 실제 1회 검증 시간 (#46 에서 실측)

## 출처

- Microsoft Learn: [Windows Sandbox overview](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-overview) · [Install](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-install) · [Use and configure (.wsb)](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file) · [Sample configuration](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-sample-configuration) · [Command line (wsb)](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-cli) · [Architecture](https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-architecture)
- Microsoft Learn: [Use WinGet (Install WinGet on Windows Sandbox)](https://learn.microsoft.com/en-us/windows/package-manager/winget/) · [about_Execution_Policies](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)
- Microsoft Learn: [Windows 11 requirements](https://learn.microsoft.com/en-us/windows/whats-new/windows-11-requirements) · [Create a virtual machine in Hyper-V](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/get-started/create-a-virtual-machine-in-hyper-v) · [Using checkpoints](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/checkpoints) · [PowerShell Direct](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/powershell-direct)
- GitHub: [winget-cli Repair-WinGetPackageManager 도움말](https://github.com/microsoft/winget-cli/blob/master/src/PowerShell/Help/Microsoft.WinGet.Client/Repair-WinGetPackageManager.md) · [winget-pkgs Tools/SandboxTest.ps1](https://github.com/microsoft/winget-pkgs/blob/master/Tools/SandboxTest.ps1) · [winget-cli#4187](https://github.com/microsoft/winget-cli/issues/4187) · winget-cli 최신 릴리스 v1.29.380 자산 크기(`gh api`)
- 그 밖: [Windows Insider Blog, Build 26220.6772](https://blogs.windows.com/windows-insider/2025/10/06/announcing-windows-11-insider-preview-build-26220-6772-dev-channel/) · [Git 2.45.1 릴리스 노트](https://code.googlesource.com/git/+/HEAD/Documentation/RelNotes/2.45.1.adoc) · [Microsoft Q&A: Windows Developer VM](https://learn.microsoft.com/en-us/answers/questions/2259075/windows-developer-vm-or-images-where-are-they-now) (사용자 보고) · [LOLBAS wsb.exe](https://lolbas-project.github.io/lolbas/OtherMSBinaries/Wsb/) (2차 출처)
