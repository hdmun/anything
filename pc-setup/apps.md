# 앱 (apps.md)

**셋업**이 설치하는 앱·**런타임**·전역 도구의 **선언**이다. 진행 방법은 [SETUP.md](SETUP.md) 를 따른다. 이 파일에는 무엇을·왜·확인 기준만 적는다. 설치 방법은 셋업할 때 공식 문서에서 찾는다.

## 기본 규칙

- **확인**: 원천마다 아래 기준으로 본다. 기준을 통과하면 `그대로`다.
  - winget·winget msstore: 그 원천의 설치 목록에 원천 힌트의 ID 가 정확히 일치하는 항목으로 있다.
  - scoop: 원천 힌트의 버킷이 추가돼 있고, 그 앱이 scoop 에 설치돼 있다.
  - nvm: `nvm` 명령이 있고, 버전 줄에 맞는 Node 가 설치돼 있으며 지금 쓰는 Node 다.
  - pnpm: pnpm 전역 설치 목록에 그 패키지가 있다.
  - go: `go env GOPATH` 의 `bin` 폴더에 그 도구의 실행 파일이 있다.
  - 공식 배포: 표 아래 그 앱의 절에 적은 기준을 쓴다.
- **버전**: 이미 설치된 앱은 버전을 올리지 않는다. 버전 줄 칸이 있는 앱만 그 줄 안의 버전이어야 한다. 업그레이드는 셋업 밖에서 한다.
- **범위**: winget 앱은 범위 칸의 범위(`user`/`machine`)로 설치한다. msstore 와 그 밖의 원천에는 범위 칸이 없다.
- **승격**: 승격 칸이 `필요`인 앱과, 범위가 `machine` 인 winget 앱은 승격 항목이다(**승격 단계**에서 맞춘다).
- **원천 준비**: scoop 이 없으면 첫 scoop 앱을 맞출 때 일반 권한으로 함께 설치한다. 계획에는 "원천 준비: scoop"으로 보인다.
- **의존**: 표의 순서대로 진행한다. 앞 항목이 `실패`면 그 항목에 의존하는 항목은 시도하지 않고 `실패: <앞 항목> 실패`로 기록한다. scoop 앱은 scoop 에, Node 는 nvm 에, pnpm 은 Node 에, pnpm 패키지는 Node·pnpm 에, go 도구는 Go 에, Ubuntu 는 WSL 에 의존한다.

## 목록

| 앱 | 원천 | 원천 힌트 | 범위 | 버전 줄 | 승격 | 왜 |
|---|---|---|---|---|---|---|
| Git | winget | `Git.Git` | user | | | |
| PowerShell 7 | winget | `Microsoft.PowerShell` | user | | | |
| Git LFS | winget | `GitHub.GitLFS` | machine | | | |
| GitHub CLI | winget | `GitHub.cli` | machine | | | |
| Fork | winget | `Fork.Fork` | user | | | |
| TortoiseGit | winget | `TortoiseGit.TortoiseGit` | machine | | | |
| Windows Terminal | winget | `Microsoft.WindowsTerminal` | user | | | |
| VS Code | winget | `Microsoft.VisualStudioCode` | user | | | |
| Notepad++ | winget | `Notepad++.Notepad++` | machine | | | |
| Visual Studio Enterprise | winget | `Microsoft.VisualStudio.Enterprise` | machine | | | |
| Rider | winget | `JetBrains.Rider` | machine | | | |
| Antigravity | winget | `Google.Antigravity` | user | | | |
| DB Browser for SQLite | winget | `DBBrowserForSQLite.DBBrowserForSQLite` | machine | | | |
| Another Redis Desktop Manager | winget | `qishibo.AnotherRedisDesktopManager` | machine | | | |
| Orca | winget | `StablyAI.Orca` | user | | | |
| 7-Zip | winget | `7zip.7zip` | machine | | | |
| Everything | winget | `voidtools.Everything` | machine | | | |
| Obsidian | winget | `Obsidian.Obsidian` | user | | | |
| Chrome | 공식 배포 | Google Chrome 설치 프로그램(안정 채널) | | | 필요 | |
| Discord | winget | `Discord.Discord` | user | | | |
| Android Studio | winget | `Google.AndroidStudio` | machine | | | |
| WinMerge | winget | `WinMerge.WinMerge` | machine | | | |
| Python | winget | `Python.Python.3.13` | user | 3.13 | 필요 | py 런처 설치에 관리자 권한이 필요하다 |
| Ruby (DevKit 포함) | winget | `RubyInstallerTeam.RubyWithDevKit.3.4` | user | 3.4 | | |
| Bun | 공식 배포 | Bun 공식 설치 스크립트 | | | | |
| Go | winget | `GoLang.Go` | machine | | | |
| gopls | go | `golang.org/x/tools/gopls` | | | | |
| staticcheck | go | `honnef.co/go/tools/cmd/staticcheck` | | | | |
| Docker Desktop | winget msstore | `XP8CBJ40XLBWKX` | | | | |
| iCloud | winget msstore | `9PKTQ5699M62` | | | | |
| lazygit | winget | `JesseDuffield.lazygit` | user | | | |
| CMake | 공식 배포 | CMake Windows 설치 프로그램(MSI) | | | | |
| DBeaver | 공식 배포 | DBeaver Community 설치 프로그램 | | | | |
| nano | scoop | main 버킷의 `nano` | | | | |
| nvm | 공식 배포 | nvm-windows 2.x 설치 프로그램 | | | | Node 버전 관리(nvm-windows 2.x) |
| Node | nvm | | | 26 | | pnpm 과 전역 패키지의 바탕 |
| pnpm | 공식 배포 | npm 전역 패키지 `pnpm` | | | | |
| Codex CLI | pnpm | `@openai/codex` | | | | |
| WSL | 공식 배포 | Windows Subsystem for Linux | | | 필요 | |
| Ubuntu | 공식 배포 | WSL 배포판 `Ubuntu-24.04` | | 24.04 | | |
| RaiDrive | 공식 배포 | RaiDrive Mount | | | 필요 | |
| D2Coding | 공식 배포 | NAVER D2Coding 글꼴 | | | | 터미널·편집기 글꼴 |
| agy | 공식 배포 | Antigravity CLI | | | | |
| Claude Code | 공식 배포 | Claude Code 네이티브 설치 | | | | |
| Flutter | 공식 배포 | Flutter SDK stable 채널 | | | | |
| NVIDIA 드라이버 | 공식 배포 | NVIDIA 그래픽 드라이버 | | | | |
| Pester | 공식 배포 | PowerShell Gallery 의 `Pester` | | 6 | | `pc-setup/tests` 를 돌리는 테스트 도구 |

## Chrome

- 확인: Windows 의 설치된 프로그램 목록에 이름이 정확히 `Google Chrome` 인 항목이 있다. `Google Chrome Beta` 같은 다른 채널은 통과하지 않는다.
- winget 목록으로 확인하지 않는다. winget 이 이미 설치된 안정 채널 Chrome 을 다른 ID(Beta)로 잘못 잡는 경우가 있다.
- 모든 사용자용으로 설치한다(승격 단계에서).

## Bun

- 확인: `~\.bun\bin\bun.exe` 가 있고, 그 폴더가 사용자 PATH 에 있다.
- 주의: PATH 는 `tools/add-user-path.ps1` 로 넣는다.

## CMake

- 확인: Windows 의 설치된 프로그램 목록에 이름이 `CMake` 인 항목이 있다.

## DBeaver

- 확인: Windows 의 설치된 프로그램 목록에 이름이 `DBeaver` 로 시작하는 항목이 있다.
- 현재 사용자용으로 설치한다(관리자 없이).

## nvm

- 확인: `nvm` 명령이 있다. 이미 설치된 nvm 1.x 도 통과한다(버전 규칙대로 올리지 않는다).
- 새로 설치할 때는 2.x 설치 프로그램을 일반 권한으로 실행한다.
- 1.x → 2.x 업그레이드는 셋업 밖에서 한다. 2.x 설치 프로그램이 1.1.7 이상의 1.x 를 옮겨 준다.

## pnpm

- 확인: `pnpm` 명령이 있고, 사용자 환경 변수 `PNPM_HOME` 이 있으며 그 폴더가 사용자 PATH 에 있다. 어떤 방법으로 설치했는지는 보지 않는다(독립 실행 스크립트로 설치한 pnpm 도 통과한다).
- 없을 때만 npm 전역 패키지로 설치한다. 그 뒤 `PNPM_HOME` 을 공식 문서의 방법으로 정한다. Node 에 의존한다.
- 주의: `PNPM_HOME` 의 PATH 추가는 [SETUP.md](SETUP.md) 의 규칙대로 `tools/add-user-path.ps1` 로 한다.

## Codex CLI

- 확인: 기본 규칙(pnpm 전역 설치 목록)에 더해, [pnpm](#pnpm) 절의 `PNPM_HOME` 기준을 통과한다.

## WSL

- 확인: WSL 패키지가 설치돼 있고, Windows 기능 `VirtualMachinePlatform` 이 켜져 있다.
- 배포판 없이 WSL 만 설치한다(배포판은 [Ubuntu](#ubuntu) 항목이 맡는다).
- 패키지는 있지만 기능이 아직 켜지지 않았으면(재부팅 전) `할 일: 재부팅 뒤 셋업을 다시 실행`이다.

## Ubuntu

- 확인: WSL 배포판 목록에 `Ubuntu-24.04` 가 있다.
- WSL 이 재부팅 전 상태면 시도하지 않고 `할 일: 재부팅 뒤 셋업을 다시 실행`이다.
- 설치할 때 배포판을 실행하지 않는다. 설치한 뒤에는 `할 일: wsl -d Ubuntu-24.04 로 처음 실행해 사용자를 만든다`로 기록한다(사용자 이름과 비밀번호는 사람이 정한다).

## RaiDrive

- 확인: Windows 의 설치된 프로그램 목록에 이름이 `RaiDrive` 로 시작하는 항목이 있다.
- 설치 프로그램이 재부팅이 필요하다고 끝나면 `할 일: 재부팅 뒤 셋업을 다시 실행`이다.

## D2Coding

- 확인: 현재 사용자 글꼴 목록에 이름이 `D2Coding` 으로 시작하는 글꼴이 있고, 그 글꼴 파일이 실제로 있다.
- 현재 사용자 글꼴로 설치한다(관리자 없이). 공식 릴리스의 모든 굵기를 담은 글꼴 묶음 파일을 쓴다.

## agy

- 확인: `agy` 실행 파일이 있고, 그 실행 파일이 든 폴더가 사용자 PATH 에 있다.
- 주의: 공식 설치 스크립트가 PATH 를 넣지 않는 경우가 있다. PATH 는 `tools/add-user-path.ps1` 로 넣는다.

## Claude Code

- 확인: `claude` 실행 파일이 있고, 그 실행 파일이 든 폴더가 사용자 PATH 의 **맨 앞**에 있다.
- PATH 는 `tools/add-user-path.ps1 -Prepend` 로 맞춘다. 다른 설치 경로(npm 등)의 `claude` 보다 먼저 잡히게 하려는 것이다.

## Flutter

- 확인: `flutter` 명령(`flutter.bat`)이 있고, 그 `bin` 폴더가 사용자 PATH 에 있다.
- stable 채널을 쓴다. Git 에 의존한다.
- Android SDK 와 라이선스 동의는 사람이 한다([README.md](README.md) 의 「손으로 할 일」).

## NVIDIA 드라이버

- 확인: 디스플레이 장치 가운데 NVIDIA 장치가 없으면 `그대로`다. NVIDIA 장치가 있으면 그 장치의 드라이버 제공자가 NVIDIA 여야 `그대로`다.
- 에이전트는 드라이버를 설치하지 않는다. 기준과 다르면 `할 일: NVIDIA 드라이버 설치`로 기록한다.

## Pester

- 확인: 현재 사용자 범위에 Pester 6.x 가 설치돼 있다.
- 현재 사용자 범위로 설치한다(관리자 없이).
