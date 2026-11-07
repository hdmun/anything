# 집 PC 현재 상태 수집 (2026-11-07)

티켓: [집 PC 의 winget 목록과 설정 파일 위치 수집](https://github.com/hdmun/anything/issues/40) · 맵: [pc-setup](https://github.com/hdmun/anything/issues/36)

공개 저장소라 개인값은 더미로 바꿨다: 이메일 → `user@example.com`, SSH 호스트 → `nas`, IP → `192.0.2.10`, 사용자 폴더 → `~` 또는 `%USERPROFILE%`.

## 핵심 사실

1. **winget 이 원천을 아는 앱은 90개뿐이다.** 나머지는 ARP 49개, MSIX 79개(대부분 Windows 기본 앱), msstore 1개(Docker Desktop). 원자료: [`pc-inventory-winget-export.json`](pc-inventory-winget-export.json) (게임 런처 3개를 뺀 88개, msstore 1개 포함).
2. **ARP 앱 8개는 winget·msstore 에 같은 앱이 있다.** 직접 설치해서 winget 이 못 알아볼 뿐이다(Chrome·Discord·Android Studio·Bun·WinMerge·RaiDrive·TableCloth·Samsung Magician).
3. **설정 파일은 전부 일반 파일이다.** symlink 는 하나도 없다. Developer Mode 는 이미 켜져 있다.
4. **scoop 이 아직 남아 있다.** 설치된 앱은 `nano` 하나다. `~/.nanorc` 가 scoop 경로를 `include` 한다. 사용자 PATH 맨 앞이 `scoop\shims` 다.
5. **Node 는 nvm-windows 가 실제로 쓰인다.** fnm 은 설치만 돼 있고 PATH 에 없다. winget 이 보는 `OpenJS.NodeJS.23` 은 실제 폴더(`C:\Program Files\nodejs`)가 없다.

## 1. 앱

### 원천별 개수

| 원천 | 개수 | 뜻 |
|---|---|---|
| winget | 90 (`winget list` 에선 125줄, 같은 ID 중복 포함) | `winget export` 에 들어감. 51개는 업데이트가 있음 |
| msstore | 1 | Docker Desktop (`XP8CBJ40XLBWKX`). export 시 "사용권 계약 필요" 경고 |
| ARP | 49 | 제어판 "프로그램 추가/제거"에만 있음. winget 원천과 연결 안 됨 |
| MSIX | 79 | 앱 패키지. 대부분 Windows 기본 앱 |

### winget 90개 (분류)

버전은 export 기준. `*` 표시는 "설치된 버전이 원천에 없음" 경고가 난 앱이다(ID 로 설치는 되지만, 지금 버전으로 고정할 수 없다).

**개발 도구 (33)**
- 편집기·IDE: `Microsoft.VisualStudioCode`, `Microsoft.VisualStudio.Enterprise` (18), `Microsoft.VisualStudio.2022.Enterprise`, `JetBrains.CLion`, `JetBrains.IntelliJIDEA.Ultimate`, `JetBrains.Rider`, `Anysphere.Cursor`, `Google.Antigravity`, `Google.AntigravityIDE`, `Notepad++.Notepad++`*
- git: `Git.Git`, `GitHub.GitLFS`, `GitHub.cli`, `GitHub.GitHubDesktop`, `TortoiseGit.TortoiseGit`, `Fork.Fork`*, `JesseDuffield.lazygit`
- 빌드·셸·터미널: `Kitware.CMake`, `MartinStorsjo.LLVM-MinGW.UCRT`, `Microsoft.PowerShell`, `Microsoft.WindowsTerminal`, `Microsoft.Sysinternals.Handle`
- DB·서버: `DBeaver.DBeaver.Community`, `DBBrowserForSQLite.DBBrowserForSQLite`, `qishibo.AnotherRedisDesktopManager`, `GrafanaLabs.Grafana.Enterprise`*, `Microsoft.msodbcsql.17`, `Microsoft.WebDeploy`*
- AI·에이전트: `StablyAI.Orca`, `GitHub.Copilot`, `Finesssee.Win-CodexBar`, `Ollama.Ollama`, `ggml.llamacpp`

**런타임·버전 매니저 (11)** — 자세한 건 [3. 런타임](#3-런타임)
- `Microsoft.DotNet.SDK.9`, `Microsoft.DotNet.DesktopRuntime.8`, `Microsoft.DotNet.DesktopRuntime.10`, `Microsoft.OpenJDK.17`, `GoLang.Go`, `OpenJS.NodeJS.23`, `CoreyButler.NVMforWindows`, `Schniz.fnm`, `Python.Python.3.13`, `Python.Launcher`, `RubyInstallerTeam.RubyWithDevKit.3.4`

**게임 엔진 (3)**: `Unity.UnityHub`*, `Unity.Unity.6000`, `Unity.Unity.2022`

**일반 앱 (13)**: `7zip.7zip`, `voidtools.Everything`, `REALiX.HWiNFO`, `SoftwareOK.Q-Dir`*, `JAMSoftware.TreeSize.Free`, `Obsidian.Obsidian`, `Google.ChromeRemoteDesktopHost`, `Microsoft.Teams`, `Microsoft.Teams.Free`, `Microsoft.Edge`, `Microsoft.OneDrive`*, `Microsoft.Outlook`*, `Microsoft.365Copilot`*

**게임 런처 (3)**: 이름 생략

**WSL 배포판 (3)**: `Microsoft.WSL`*, `Canonical.Ubuntu.2204`*, `Canonical.Ubuntu.2404`*

**재배포 라이브러리 (24)**
- `Microsoft.VCRedist.*` 8개 (2010·2012·2013·2015+, x86/x64), `Nvidia.PhysX`
- `Microsoft.UI.Xaml.2.6`/`2.7`*/`2.8`*, `Microsoft.VCLibs.14`, `Microsoft.VCLibs.Desktop.14`, `Microsoft.DotNet.Native.Runtime`
- `Microsoft.WindowsAppRuntime.1.1`·`1.2`·`1.4`~`1.8`*, `Microsoft.WindowsAppRuntime.2`*
- `Microsoft.AppInstaller` (winget 자체)

### ARP 49개 (분류)

**winget·msstore 에 같은 앱이 있음 (8)**

| 설치된 이름 | 후보 ID | 원천 |
|---|---|---|
| Google Chrome | `Google.Chrome` | winget |
| Discord | `Discord.Discord` | winget |
| Android Studio | `Google.AndroidStudio` | winget |
| Bun | `Oven-sh.Bun` | winget |
| WinMerge | `WinMerge.WinMerge` | winget |
| RaiDrive | `OpenBoxLab.RaiDrive` | winget |
| TableCloth | `TableClothProject.TableCloth` | winget |
| Samsung Magician | `XPDDT99J9GKB5C` | msstore |

**다른 설치에 딸려 온 것 (20)**
- Visual Studio 가 설치: Visual Studio Installer, .NET SDK 9.0.307·10.0.102, Windows SDK 2개, Windows SDK AddOn, IIS 10.0 Express, SQL Server LocalDB 2019·2025 RC1, SQL Server 2019 CLR Types, vs_CoreEditorFonts
- JetBrains: JetBrains ETW Host Service
- NVIDIA: 그래픽 드라이버, NVIDIA App, FrameView SDK
- Windows: WSL Update, Update Health Tools, Application Compatibility Fix Database
- Edge 기반: Copilot
- Chrome: "Chrome 원격 데스크톱" (Chrome 웹 앱 바로가기)

**winget 에 없음 (21)**
- 오피스: Office Professional Plus 2019, Microsoft 365 앱 (winget ID 는 확인 안 함)
- 미디어·편집: Adobe Premiere Pro 2023, KMPlayer 64X
- 게임·게임 런처 10개 (이름 생략)
- 은행 보안 플러그인 2개 (이름 생략)
- 기타: iCloud Outlook, VIA-C, YES24 eBook, 2Ace, 금융 앱 1개(이름 생략)

### MSIX 79개

Windows 기본 앱·코덱·언어 팩이 대부분이다(계산기·사진·Xbox·HEVC 확장 등). 기본 앱이 아닌 것만 추린다.

| 이름 | 패키지 | 비고 |
|---|---|---|
| ChatGPT Classic | `OpenAI.ChatGPT-Desktop` | Store 앱 |
| iCloud | `AppleInc.iCloud` | Store 앱 |
| Microsoft Clipchamp | `Clipchamp.Clipchamp` | Store 앱 |
| Windows Sandbox | `MicrosoftWindows.WindowsSandbox` | Windows 기능(선택 기능 켜기) |
| Notepad++ · WinMerge · TortoiseGit · TreeSize | — | 각 앱이 설치한 탐색기 메뉴 확장 |
| NVIDIA Control Panel | `NVIDIACorp.NVIDIAControlPanel` | 드라이버가 설치 |
| Local AI Manager for Microsoft 365 | `aimgr` | Office 가 설치 |

### 그 밖의 설치 (winget·ARP·MSIX 어디에도 없음)

| 항목 | 위치 | 방식 |
|---|---|---|
| nano | `~/scoop/apps/nano` | scoop (scoop 앱은 이것 하나) |
| D2Coding 폰트 1.3.2 | `%LOCALAPPDATA%\Microsoft\Windows\Fonts` | 사용자 폰트 수동 설치. winget 에 없음. Windows Terminal 기본 폰트 |
| Flutter | `~/develop/flutter` | 수동 설치(zip·git) |
| pnpm | `%LOCALAPPDATA%\pnpm` | 설치 방식 미확인 |
| agy CLI | `%LOCALAPPDATA%\agy\bin` | 설치 방식 미확인 |

## 2. 설정 파일 (범위 2)

모두 일반 파일이다. symlink·hardlink 없음.

| 파일 | 실제 경로 | 크기·수정일 | 내용 |
|---|---|---|---|
| `$PROFILE` (pwsh 7) | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` | 407B · 2026-11-06 | `claude-sub` 함수 + `~/scripts/agent-accounts/AgentAccounts.ps1` dot-source (절대 경로) |
| `$PROFILE` (Windows PowerShell 5.1) | `~/Documents/WindowsPowerShell/Microsoft.PowerShell_profile.ps1` | 345B · 2026-10-08 | `claude-sub` 함수만. pwsh 7 쪽과 중복, agent-accounts 없음 |
| `~/.gitconfig` | `~/.gitconfig` | 221B · 2026-08-28 | `user.name`, `user.email`(`user@example.com`), `filter "lfs"`(git lfs install 이 씀), `core.longpaths = true`. `[include]` 없음 |
| `~/.ssh/config` | `~/.ssh/config` | 47B · 2025-01-06 | `Host nas` 하나. `HostName` 과 `User` 값이 뒤바뀐 것으로 보임(`User` 칸에 IP `192.0.2.10`). 키는 `id_ed25519_nas` 하나 |
| Windows Terminal | `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` | 5206B · 2026-09-04 | 아래 참고 |
| VS Code 설정 | `%APPDATA%\Code\User\settings.json` | 1096B · 2026-09-12 | 포매터·autoSave·Claude Code 패널 위치 등. `geminicodeassist.project` 에 개인 GCP 프로젝트 ID |
| VS Code 키 바인딩 | `%APPDATA%\Code\User\keybindings.json` | 265B · 2024-11-10 | 바인딩 해제 1개(vueBeautify) |

### 없는 경로 (확인함)

- `~/Documents/PowerShell/profile.ps1`, `Microsoft.VSCode_profile.ps1`, `~/.config/git/config`, `~/.gitconfig.local`
- Windows Terminal Preview·비패키지 경로의 `settings.json`
- VS Code `snippets/` 는 비어 있음. `profiles/` 는 `builtin` 하나

### 함께 알아둘 것

- **Documents 는 OneDrive 로 옮겨져 있지 않다.** `$PROFILE` 경로가 `~/Documents/...` 그대로다.
- **Windows Terminal 기본 프로필이 Windows PowerShell 5.1 이다** (`{61c54bbd-…}`). pwsh 7 프로필은 `PowerShell`·`PowerShell 7` 두 개가 동적 생성돼 있다. 프로필 14개 중 직접 만든 건 PowerShell 5.1·cmd 두 개뿐이고, 나머지는 VS·WSL·Ubuntu·Azure·PowerShellCore 가 자동 생성했다. `profiles.defaults` 는 폰트(`D2Coding`)만 있다.
- **VS Code 확장 24개**: `anthropic.claude-code`, `golang.go`, `ms-dotnettools.csharp`, `ms-python.python`, `ms-vscode.powershell`, `ms-vscode.cpptools`·`cmake-tools`, `ms-vscode-remote.*`(SSH·WSL·Containers), `esbenp.prettier-vscode`, `dbaeumer.vscode-eslint`, `octref.vetur` 등. 목록은 `code --list-extensions` 로 다시 뽑을 수 있다.
- **`~/.nanorc` (11979B)** 는 nano 샘플 파일에 `include "~/scoop/apps/nano/current/syntax/*.nanorc"` 한 줄을 더한 것이다. winget `okibcn.nano` 로 옮기면 이 경로를 바꿔야 한다.
- **에이전트 설정 폴더** (홈 아래): `.claude`, `.claude-sub`, `.codex`, `.gemini`, `.cursor`, `.copilot`, `.antigravity*`, `.orca`, `.agent-accounts`, `.relay` 등 20개 이상.

## 3. 런타임

| 런타임 | 실제로 쓰이는 것 | 경로 | 설치 방식 |
|---|---|---|---|
| .NET | SDK 9.0.123 · 9.0.307 · 10.0.102, 런타임 3.1~10.0.14 여러 개 | `C:\Program Files\dotnet` | SDK 9.0.123 은 winget `Microsoft.DotNet.SDK.9`. 9.0.307·10.0.102 는 Visual Studio 가 설치. 데스크톱 런타임 8·10 은 winget. `DOTNET_ROOT` 없음 |
| JDK | OpenJDK 17.0.18 (Microsoft) | `C:\Program Files\Microsoft\jdk-17.0.18.8-hotspot` | winget `Microsoft.OpenJDK.17`. `JAVA_HOME` 설정됨, 시스템 PATH 맨 앞. 별도로 `~/.jdks/openjdk-23.0.1` (IntelliJ 가 받은 것) |
| Go | 1.23.5 | `C:\Program Files\Go` | winget `GoLang.Go`. `GOPATH=~/go` |
| Node | 23.3.0 | `C:\nvm4w\nodejs` → `%LOCALAPPDATA%\nvm\v23.3.0` (symlink) | nvm-windows (winget `CoreyButler.NVMforWindows` 1.2.2). npm 전역은 `%APPDATA%\npm` |
| Bun | 1.3.13 | `~/.bun/bin` | 공식 설치 스크립트(ARP `User\Bun`, 버전 Unknown). winget `Oven-sh.Bun` 있음 |
| Python (참고) | 3.13.0 | `%LOCALAPPDATA%\Programs\Python\Python313` | winget `Python.Python.3.13` (사용자 범위) + `Python.Launcher` |
| Ruby (참고) | 3.4.8 | `C:\Ruby34-x64` | winget `RubyInstallerTeam.RubyWithDevKit.3.4` |

Node 쪽 겹침:

- `Schniz.fnm` 1.38.1 은 winget 패키지 폴더에만 있고 PATH·`WinGet\Links` 에 없다.
- winget 은 `OpenJS.NodeJS.23` 이 설치됐다고 보지만 `C:\Program Files\nodejs` 가 없다. ARP 항목만 남은 것으로 보인다.

## 4. PATH 관찰 (드리프트 입력)

- **사용자 PATH 가 시스템 PATH 를 거의 통째로 복사해 두었다.** `system32`, Git, CMake, Go, Python, dotnet, nvm 등이 양쪽에 다 있다.
- **없는 경로가 남아 있다**: `C:\Ruby33-x64\bin` (지금은 3.4), 중간에 잘린 `%LOCALAPPDATA%\Microso`.
- 사용자 PATH 에 `~/.dotnet/tools` 가 두 번 있다.
- winget portable 앱 중 llama.cpp·LLVM-MinGW 는 `WinGet\Links` 대신 패키지 폴더를 PATH 에 직접 넣었다.
- 사용자 PATH 맨 앞이 `~/scoop/shims` 다.

## 다시 뽑는 법

```powershell
winget export -o winget-export.json --include-versions --accept-source-agreements
winget list --accept-source-agreements --disable-interactivity   # ARP·MSIX 포함 전체
code --list-extensions
Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'   # Developer Mode
[Environment]::GetEnvironmentVariable('Path','User') -split ';'
```

`winget list` 는 이름 칸에 한글이 섞여 칸 폭이 어긋난다. 동아시아 문자 폭(2칸)을 계산해 잘라야 ID 를 정확히 읽는다.
