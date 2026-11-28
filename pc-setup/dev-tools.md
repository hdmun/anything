# 개발툴 (dev-tools.md)

**셋업**이 **확인만** 하는 **개발툴**의 **선언**이다. 진행 방법은 [SETUP.md](SETUP.md) 를 따른다. 셋업은 이 파일의 항목을 설치·업그레이드하지 않는다. 설치는 사람이 설치 안내 칸대로 손으로 한다. 셋업이 설치하는 기반 도구(Git·PowerShell 7·Python·Go·nvm·Node·pnpm)와 개발툴이 아닌 앱은 [apps.md](apps.md) 에 있다.

## 기본 규칙

- **확인**: 원천마다 아래 기준으로 본다. 기준을 통과하면 `그대로`, 통과하지 못하면 `할 일: <설치 안내>` 다.
  - winget·winget msstore: [apps.md](apps.md) 「기본 규칙」의 같은 원천 기준을 쓴다.
  - scoop: 그 앱이 scoop 에 설치돼 있다. scoop 이 없으면 통과하지 못한다.
  - pnpm: pnpm 전역 설치 목록에 그 패키지가 있다. pnpm 이 없으면 통과하지 못한다.
  - go: `go env GOPATH` 의 `bin` 폴더에 그 도구의 실행 파일이 있다. Go 가 없으면 통과하지 못한다.
  - 공식 배포: 표 아래 그 항목의 절에 적은 기준을 쓴다.
- **버전**: 확인하지 않는다. 어느 버전이든 설치돼 있으면 `그대로`다.
- **바꾸지 않음**: 확인 기준에 PATH 가 있어도 셋업은 PATH 를 맞추지 않는다. 기준을 통과하지 못하면 `할 일` 이다.
- **확인 못 함**: 일반 권한으로 확인하지 못하면 `실패: 확인 못 함 (<이유>)` 다.
- **설치 안내**: 사람이 실행할 명령이나 방법이다. `할 일:` 에 그대로 옮긴다. 공식 배포 항목은 방법이 바뀔 수 있어 어디에서 찾는지만 적는다.
- 선언 밖 npm 패키지는 `pnpm`, go 도구는 `go install` 로 설치한다. 둘 다 [apps.md](apps.md) 의 기반 도구라 셋업이 먼저 설치한다.

## Git·버전 관리

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| Git LFS | winget | `GitHub.GitLFS` | `winget install --id GitHub.GitLFS -e --scope machine` |
| GitHub CLI | winget | `GitHub.cli` | `winget install --id GitHub.cli -e --scope machine` |
| Fork | winget | `Fork.Fork` | `winget install --id Fork.Fork -e --scope user` |
| TortoiseGit | winget | `TortoiseGit.TortoiseGit` | `winget install --id TortoiseGit.TortoiseGit -e --scope machine` |
| lazygit | winget | `JesseDuffield.lazygit` | `winget install --id JesseDuffield.lazygit -e --scope user` |
| WinMerge | winget | `WinMerge.WinMerge` | `winget install --id WinMerge.WinMerge -e --scope machine` |
| Gitleaks | winget | `Gitleaks.Gitleaks` | `winget install --id Gitleaks.Gitleaks -e --scope user` |
| git-filter-repo | scoop | main 버킷의 `git-filter-repo` | `scoop install main/git-filter-repo` |
| GitHub Desktop | winget | `GitHub.GitHubDesktop` | `winget install --id GitHub.GitHubDesktop -e` |

## 셸·터미널·작은 도구

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| Windows Terminal | winget | `Microsoft.WindowsTerminal` | `winget install --id Microsoft.WindowsTerminal -e --scope user` |
| nano | scoop | main 버킷의 `nano` | `scoop install main/nano` |
| Sysinternals Handle | winget | `Microsoft.Sysinternals.Handle` | `winget install --id Microsoft.Sysinternals.Handle -e --scope user` |
| Pester | 공식 배포 | PowerShell Gallery 의 `Pester` | `Install-Module Pester -Scope CurrentUser -MinimumVersion 6.0.0 -Force -SkipPublisherCheck` |

## IDE·편집기

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| VS Code | winget | `Microsoft.VisualStudioCode` | `winget install --id Microsoft.VisualStudioCode -e --scope user` |
| Notepad++ | winget | `Notepad++.Notepad++` | `winget install --id Notepad++.Notepad++ -e --scope machine` |
| Visual Studio Enterprise | winget | `Microsoft.VisualStudio.Enterprise` | `winget install --id Microsoft.VisualStudio.Enterprise -e --scope machine` |
| Visual Studio Enterprise 2022 | winget | `Microsoft.VisualStudio.2022.Enterprise` | `winget install --id Microsoft.VisualStudio.2022.Enterprise -e` |
| Rider | winget | `JetBrains.Rider` | `winget install --id JetBrains.Rider -e --scope machine` |
| CLion | winget | `JetBrains.CLion` | `winget install --id JetBrains.CLion -e` |
| IntelliJ IDEA Ultimate | winget | `JetBrains.IntelliJIDEA.Ultimate` | `winget install --id JetBrains.IntelliJIDEA.Ultimate -e` |
| Cursor | winget | `Anysphere.Cursor` | `winget install --id Anysphere.Cursor -e` |
| Antigravity | winget | `Google.Antigravity` | `winget install --id Google.Antigravity -e --scope user` |
| Antigravity IDE | winget | `Google.AntigravityIDE` | `winget install --id Google.AntigravityIDE -e` |
| Android Studio | winget | `Google.AndroidStudio` | `winget install --id Google.AndroidStudio -e --scope machine` |
| Orca | winget | `StablyAI.Orca` | `winget install --id StablyAI.Orca -e --scope user` |
| Unity Hub | winget | `Unity.UnityHub` | `winget install --id Unity.UnityHub -e` |
| Unity 2022 에디터 | winget | `Unity.Unity.2022` | `winget install --id Unity.Unity.2022 -e` (Unity Hub 에서 설치해도 된다) |
| Unity 6000 에디터 | winget | `Unity.Unity.6000` | `winget install --id Unity.Unity.6000 -e` (Unity Hub 에서 설치해도 된다) |

## AI 도구

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| Claude Code | 공식 배포 | Claude Code 네이티브 설치 | Claude Code 공식 문서의 Windows 네이티브 설치. 그 뒤 PATH 는 [Claude Code](#claude-code) 절대로 맞춘다 |
| agy | 공식 배포 | Antigravity CLI | Antigravity 공식 문서의 CLI 설치 스크립트. 그 뒤 PATH 는 [agy](#agy) 절대로 맞춘다 |
| Codex CLI | pnpm | `@openai/codex` | `pnpm add -g @openai/codex` |
| Copilot CLI | winget | `GitHub.Copilot` | `winget install --id GitHub.Copilot -e` |
| Gemini CLI | pnpm | `@google/gemini-cli` | `pnpm add -g @google/gemini-cli` |
| opencode | pnpm | `opencode-ai` | `pnpm add -g opencode-ai` |
| ui-ux-pro-max-cli | pnpm | `ui-ux-pro-max-cli` | `pnpm add -g ui-ux-pro-max-cli` |
| Ollama | winget | `Ollama.Ollama` | `winget install --id Ollama.Ollama -e` |
| llama.cpp | winget | `ggml.llamacpp` | `winget install --id ggml.llamacpp -e` |
| Paseo | winget | `Paseo.Paseo` | `winget install --id Paseo.Paseo -e` |
| CodexBar | winget | `Finesssee.Win-CodexBar` | `winget install --id Finesssee.Win-CodexBar -e` |

## 런타임·SDK

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| Ruby 3.4 (DevKit 포함) | winget | `RubyInstallerTeam.RubyWithDevKit.3.4` | `winget install --id RubyInstallerTeam.RubyWithDevKit.3.4 -e --scope user` |
| Bun | 공식 배포 | Bun 공식 설치 스크립트 | Bun 공식 문서의 Windows 설치 스크립트. PATH 가 없으면 `pwsh -NoProfile -File tools/add-user-path.ps1 -Entry <bun 폴더>` |
| Flutter | 공식 배포 | Flutter SDK stable 채널 | Flutter 공식 문서의 Windows 설치(stable 채널). `bin` 폴더는 `pwsh -NoProfile -File tools/add-user-path.ps1 -Entry <flutter\bin>` 으로 PATH 에 넣는다 |
| CMake | 공식 배포 | CMake Windows 설치 프로그램(MSI) | CMake 공식 다운로드 페이지의 Windows 설치 프로그램(MSI) |
| .NET SDK 9 | winget | `Microsoft.DotNet.SDK.9` | `winget install --id Microsoft.DotNet.SDK.9 -e` |
| OpenJDK 17 | winget | `Microsoft.OpenJDK.17` | `winget install --id Microsoft.OpenJDK.17 -e` |
| LLVM MinGW (UCRT) | winget | `MartinStorsjo.LLVM-MinGW.UCRT` | `winget install --id MartinStorsjo.LLVM-MinGW.UCRT -e` |
| Node.js 23 | winget | `OpenJS.NodeJS.23` | 꼭 필요할 때만 `winget install --id OpenJS.NodeJS.23 -e` (주의: [apps.md](apps.md) 의 nvm 이 Node 를 맡아 겹친다) |
| fnm | winget | `Schniz.fnm` | 꼭 필요할 때만 `winget install --id Schniz.fnm -e` (주의: [apps.md](apps.md) 의 nvm 과 같은 일을 하는 Node 버전 관리자라 겹친다) |

## Go 도구

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| gopls | go | `golang.org/x/tools/gopls` | `go install golang.org/x/tools/gopls@latest` |
| staticcheck | go | `honnef.co/go/tools/cmd/staticcheck` | `go install honnef.co/go/tools/cmd/staticcheck@latest` |
| buf | go | `github.com/bufbuild/buf/cmd/buf` | `go install github.com/bufbuild/buf/cmd/buf@latest` |
| protoc-gen-go | go | `google.golang.org/protobuf/cmd/protoc-gen-go` | `go install google.golang.org/protobuf/cmd/protoc-gen-go@latest` |
| protoc-gen-go-grpc | go | `google.golang.org/grpc/cmd/protoc-gen-go-grpc` | `go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest` |

## 컨테이너·Linux

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| Docker Desktop | winget msstore | `XP8CBJ40XLBWKX` | `winget install --id XP8CBJ40XLBWKX -e --source msstore` |
| WSL | 공식 배포 | Windows Subsystem for Linux | 관리자 창에서 `wsl --install --no-distribution` 뒤 재부팅 |
| Ubuntu 24.04 | 공식 배포 | WSL 배포판 `Ubuntu-24.04` | `wsl --install -d Ubuntu-24.04` 뒤 처음 실행해 사용자를 만든다 |

## DB·서버

| 개발툴 | 원천 | 원천 힌트 | 설치 안내 |
|---|---|---|---|
| DB Browser for SQLite | winget | `DBBrowserForSQLite.DBBrowserForSQLite` | `winget install --id DBBrowserForSQLite.DBBrowserForSQLite -e --scope machine` |
| Another Redis Desktop Manager | winget | `qishibo.AnotherRedisDesktopManager` | `winget install --id qishibo.AnotherRedisDesktopManager -e --scope machine` |
| DBeaver | 공식 배포 | DBeaver Community 설치 프로그램 | DBeaver 공식 다운로드 페이지의 Community 설치 프로그램을 현재 사용자용으로 실행한다 |
| Grafana Enterprise | winget | `GrafanaLabs.Grafana.Enterprise` | `winget install --id GrafanaLabs.Grafana.Enterprise -e` |
| SQL Server LocalDB 2019·2025 | 공식 배포 | Visual Studio 설치 프로그램의 「SQL Server Express LocalDB」 구성 요소 | Visual Studio 설치 프로그램에서 「SQL Server Express LocalDB」 구성 요소를 고른다 |
| ODBC Driver 17 for SQL Server | winget | `Microsoft.msodbcsql.17` | `winget install --id Microsoft.msodbcsql.17 -e` |
| Web Deploy | winget | `Microsoft.WebDeploy` | `winget install --id Microsoft.WebDeploy -e` |

## Pester

- 확인: 현재 사용자 범위에 Pester 모듈이 있다. Windows 에 함께 들어 있는 모든 사용자 범위의 Pester 는 세지 않는다.
- `pc-setup/tests` 는 Pester 6 으로 돈다. 그래서 설치 안내에 6 이상을 적는다.

## Unity 에디터

- 확인: winget 설치 목록에 원천 힌트의 ID 가 있거나, Unity Hub 의 에디터 설치 폴더(Hub 설정의 설치 위치) 아래에 이름이 그 버전 줄(`2022.`·`6000.`)로 시작하는 폴더가 있고 그 안에 `Editor\Unity.exe` 가 있다.

## Claude Code

- 확인: `claude` 실행 파일이 있고, 그 실행 파일이 든 폴더가 사용자 PATH 의 **맨 앞**에 있다.
- PATH 가 맨 앞이 아니면 `할 일: pwsh -NoProfile -File tools/add-user-path.ps1 -Entry <claude 폴더> -Prepend` 다. 다른 설치 경로(npm 등)의 `claude` 보다 먼저 잡히게 하려는 것이다.

## agy

- 확인: `agy` 실행 파일이 있고, 그 실행 파일이 든 폴더가 사용자 PATH 에 있다.
- 공식 설치 스크립트가 PATH 를 넣지 않는 경우가 있다. PATH 만 없으면 `할 일: pwsh -NoProfile -File tools/add-user-path.ps1 -Entry <agy 폴더>` 다.

## Codex CLI

- 확인: 기본 규칙(pnpm 전역 설치 목록)에 더해, [apps.md](apps.md) 「pnpm」 절의 `PNPM_HOME` 기준을 통과한다.

## Bun

- 확인: `bun` 명령이 있다.

## Flutter

- 확인: `flutter` 명령(`flutter.bat`)이 있고, 그 `bin` 폴더가 사용자 PATH 에 있다.
- Android SDK 와 라이선스 동의는 사람이 한다([README.md](README.md) 의 「손으로 할 일」).

## CMake

- 확인: Windows 의 설치된 프로그램 목록에 이름이 `CMake` 인 항목이 있다.

## WSL

- 확인: WSL 패키지가 설치돼 있고, Windows 기능 `VirtualMachinePlatform` 이 켜져 있다.
- 패키지는 있지만 기능이 아직 켜지지 않았으면(재부팅 전) `할 일: 재부팅` 이다.

## Ubuntu 24.04

- 확인: WSL 배포판 목록에 `Ubuntu-24.04` 가 있다. WSL 이 없으면 통과하지 못한다.

## DBeaver

- 확인: Windows 의 설치된 프로그램 목록에 이름이 `DBeaver` 로 시작하는 항목이 있다.

## SQL Server LocalDB 2019·2025

- 확인: Windows 의 설치된 프로그램 목록에 이름이 `Microsoft SQL Server 2019 LocalDB` 로 시작하는 항목과 `Microsoft SQL Server 2025 LocalDB` 로 시작하는 항목이 둘 다 있다.

## git-filter-repo

- 실행에 Python 과 Git 이 필요하다. 둘 다 [apps.md](apps.md) 의 기반 도구다.
