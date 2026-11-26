# 개발툴 체크리스트 (dev-tools.md)

새 PC 에서 사람이 보고 체크하는 개발툴 목록이다. **셋업은 이 파일을 읽지 않는다.** 셋업이 설치하는 항목의 원본은 [apps.md](apps.md) 다. 두 파일이 다르면 `apps.md` 가 맞다.

- `셋업이 설치`: `apps.md` 의 **선언**에 있다. **셋업**이 끝나면 체크한다.
- 그 밖의 항목: 선언 밖이다. 적힌 명령이나 방법으로 손으로 설치한다.
- 선언 밖 npm 패키지는 `pnpm`, go 도구는 `go install` 로 설치한다. 둘 다 셋업이 먼저 설치한다.

## Git·버전 관리

- [ ] Git — 셋업이 설치 (winget `Git.Git`)
- [ ] Git LFS — 셋업이 설치 (winget `GitHub.GitLFS`)
- [ ] GitHub CLI — 셋업이 설치 (winget `GitHub.cli`)
- [ ] Fork — 셋업이 설치 (winget `Fork.Fork`)
- [ ] TortoiseGit — 셋업이 설치 (winget `TortoiseGit.TortoiseGit`)
- [ ] lazygit — 셋업이 설치 (winget `JesseDuffield.lazygit`)
- [ ] WinMerge — 셋업이 설치 (winget `WinMerge.WinMerge`)
- [ ] Gitleaks — 셋업이 설치 (winget `Gitleaks.Gitleaks`)
- [ ] git-filter-repo — 셋업이 설치 (scoop main 버킷 `git-filter-repo`)
- [ ] GitHub Desktop — winget `GitHub.GitHubDesktop`: `winget install --id GitHub.GitHubDesktop -e`

## 셸·터미널·작은 도구

- [ ] PowerShell 7 — 셋업이 설치 (winget `Microsoft.PowerShell`)
- [ ] Windows Terminal — 셋업이 설치 (winget `Microsoft.WindowsTerminal`)
- [ ] nano — 셋업이 설치 (scoop main 버킷 `nano`)
- [ ] Sysinternals Handle — 셋업이 설치 (winget `Microsoft.Sysinternals.Handle`)
- [ ] Pester — 셋업이 설치 (PowerShell Gallery `Pester` 6)

## IDE·편집기

- [ ] VS Code — 셋업이 설치 (winget `Microsoft.VisualStudioCode`)
- [ ] Notepad++ — 셋업이 설치 (winget `Notepad++.Notepad++`)
- [ ] Visual Studio Enterprise — 셋업이 설치 (winget `Microsoft.VisualStudio.Enterprise`)
- [ ] Rider — 셋업이 설치 (winget `JetBrains.Rider`)
- [ ] Antigravity — 셋업이 설치 (winget `Google.Antigravity`)
- [ ] Android Studio — 셋업이 설치 (winget `Google.AndroidStudio`)
- [ ] Orca — 셋업이 설치 (winget `StablyAI.Orca`)
- [ ] Visual Studio Enterprise 2022 — winget `Microsoft.VisualStudio.2022.Enterprise`: `winget install --id Microsoft.VisualStudio.2022.Enterprise -e` (선언의 `Microsoft.VisualStudio.Enterprise` 와 다른 ID 다)
- [ ] CLion — winget `JetBrains.CLion`: `winget install --id JetBrains.CLion -e`
- [ ] IntelliJ IDEA Ultimate — winget `JetBrains.IntelliJIDEA.Ultimate`: `winget install --id JetBrains.IntelliJIDEA.Ultimate -e`
- [ ] Cursor — winget `Anysphere.Cursor`: `winget install --id Anysphere.Cursor -e`
- [ ] Antigravity IDE — winget `Google.AntigravityIDE`: `winget install --id Google.AntigravityIDE -e`
- [ ] Unity Hub — winget `Unity.UnityHub`: `winget install --id Unity.UnityHub -e`
  - [ ] Unity 2022 에디터 — winget `Unity.Unity.2022`: `winget install --id Unity.Unity.2022 -e` (Unity Hub 에서 설치해도 된다)
  - [ ] Unity 6000 에디터 — winget `Unity.Unity.6000`: `winget install --id Unity.Unity.6000 -e` (Unity Hub 에서 설치해도 된다)

## AI 도구

- [ ] Claude Code — 셋업이 설치 (공식 배포, 네이티브 설치)
- [ ] agy — 셋업이 설치 (공식 배포, Antigravity CLI)
- [ ] Codex CLI — 셋업이 설치 (pnpm `@openai/codex`)
- [ ] Copilot CLI — winget `GitHub.Copilot`: `winget install --id GitHub.Copilot -e`
- [ ] Gemini CLI — npm `@google/gemini-cli`: `pnpm add -g @google/gemini-cli`
- [ ] opencode — npm `opencode-ai`: `pnpm add -g opencode-ai`
- [ ] ui-ux-pro-max-cli — npm `ui-ux-pro-max-cli`: `pnpm add -g ui-ux-pro-max-cli`
- [ ] Ollama — winget `Ollama.Ollama`: `winget install --id Ollama.Ollama -e`
- [ ] llama.cpp — winget `ggml.llamacpp`: `winget install --id ggml.llamacpp -e`
- [ ] Paseo — winget `Paseo.Paseo`: `winget install --id Paseo.Paseo -e`
- [ ] CodexBar — winget `Finesssee.Win-CodexBar`: `winget install --id Finesssee.Win-CodexBar -e`

## 런타임·SDK

- [ ] Python 3.13 — 셋업이 설치 (winget `Python.Python.3.13`)
- [ ] Ruby 3.4 (DevKit 포함) — 셋업이 설치 (winget `RubyInstallerTeam.RubyWithDevKit.3.4`)
- [ ] Bun — 셋업이 설치 (공식 배포, 설치 스크립트)
- [ ] Go — 셋업이 설치 (winget `GoLang.Go`)
- [ ] nvm — 셋업이 설치 (공식 배포, nvm-windows 2.x)
- [ ] Node 26 — 셋업이 설치 (nvm)
- [ ] pnpm — 셋업이 설치 (공식 배포, npm 전역 패키지 `pnpm`)
- [ ] Flutter — 셋업이 설치 (공식 배포, stable 채널)
- [ ] CMake — 셋업이 설치 (공식 배포, MSI)
- [ ] .NET SDK 9 — winget `Microsoft.DotNet.SDK.9`: `winget install --id Microsoft.DotNet.SDK.9 -e`
- [ ] OpenJDK 17 — winget `Microsoft.OpenJDK.17`: `winget install --id Microsoft.OpenJDK.17 -e`
- [ ] LLVM MinGW (UCRT) — winget `MartinStorsjo.LLVM-MinGW.UCRT`: `winget install --id MartinStorsjo.LLVM-MinGW.UCRT -e`
- [ ] Node.js 23 — winget `OpenJS.NodeJS.23`: `winget install --id OpenJS.NodeJS.23 -e` (주의: 선언의 nvm 이 Node 를 맡는다. 겹치므로 꼭 필요할 때만 설치한다)
- [ ] fnm — winget `Schniz.fnm`: `winget install --id Schniz.fnm -e` (주의: 선언의 nvm 과 같은 일을 하는 Node 버전 관리자다. 겹치므로 꼭 필요할 때만 설치한다)

## Go 도구

- [ ] gopls — 셋업이 설치 (go `golang.org/x/tools/gopls`)
- [ ] staticcheck — 셋업이 설치 (go `honnef.co/go/tools/cmd/staticcheck`)
- [ ] buf — `go install github.com/bufbuild/buf/cmd/buf@latest`
- [ ] protoc-gen-go — `go install google.golang.org/protobuf/cmd/protoc-gen-go@latest`
- [ ] protoc-gen-go-grpc — `go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest`

## 컨테이너·Linux

- [ ] Docker Desktop — 셋업이 설치 (winget msstore `XP8CBJ40XLBWKX`)
- [ ] WSL — 셋업이 설치 (공식 배포)
- [ ] Ubuntu 24.04 — 셋업이 설치 (공식 배포, WSL 배포판 `Ubuntu-24.04`)

## DB·서버

- [ ] DB Browser for SQLite — 셋업이 설치 (winget `DBBrowserForSQLite.DBBrowserForSQLite`)
- [ ] Another Redis Desktop Manager — 셋업이 설치 (winget `qishibo.AnotherRedisDesktopManager`)
- [ ] DBeaver — 셋업이 설치 (공식 배포, Community 설치 프로그램)
- [ ] Grafana Enterprise — winget `GrafanaLabs.Grafana.Enterprise`: `winget install --id GrafanaLabs.Grafana.Enterprise -e`
- [ ] SQL Server LocalDB 2019·2025 — Visual Studio 설치 프로그램에서 「SQL Server Express LocalDB」 구성 요소를 고른다
- [ ] ODBC Driver 17 for SQL Server — winget `Microsoft.msodbcsql.17`: `winget install --id Microsoft.msodbcsql.17 -e`
- [ ] Web Deploy — winget `Microsoft.WebDeploy`: `winget install --id Microsoft.WebDeploy -e`
