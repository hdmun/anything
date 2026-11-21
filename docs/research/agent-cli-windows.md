# 에이전트 CLI 가 Windows 에서 md 지시문으로 셋업을 진행하는 방법: Claude Code·agy·Codex

- 질문: [#138](https://github.com/hdmun/anything/issues/138) (지도 [#137](https://github.com/hdmun/anything/issues/137))
- 조사일: 2026-11-21
- 로컬에서 `--help` 로 확인한 버전: Claude Code 2.1.330, Codex CLI 0.159.3, Antigravity CLI(agy) 1.5.13
- 표기: 출처 링크가 붙은 문장은 그 공식 문서·공식 저장소에 적힌 사실이다. **[추론]** 은 문서 사실에서 끌어낸 판단이다. **[확인 못 함]** 은 1차 자료에서 찾지 못한 것이다.

## 요약

| 항목 | Claude Code | Antigravity CLI (agy) | Codex CLI |
| - | - | - | - |
| 설치(PowerShell 한 줄) | `irm https://claude.ai/install.ps1 \| iex` | `irm https://antigravity.google/cli/install.ps1 \| iex` | `powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 \| iex"` |
| winget | `winget install Anthropic.ClaudeCode` (공식) | 공식 문서에 없음 | 공식 문서에 없음 |
| 로그인 | `claude` 첫 실행 → 브라우저, 또는 `ANTHROPIC_API_KEY` | `agy` 첫 실행 → 브라우저(키링 재사용), SSH 면 URL+코드, `GEMINI_API_KEY`+설정 | `codex login`(브라우저), `--device-auth`, `--with-api-key` |
| 프로젝트 지시문 | `CLAUDE.md`, 없으면 `AGENTS.md` | `AGENTS.md`·`GEMINI.md`·`.agents/rules/*.md` 모두 누적 | `AGENTS.override.md` → `AGENTS.md` → fallback 이름 |
| 첫 프롬프트로 시작 | `claude "..."` | `agy -i "..."` | `codex "..."` |
| 비대화형 | `claude -p "..."` | `agy -p "..."` | `codex exec "..."` |
| 네이티브 Windows 샌드박스 | 없음 | 있음(AppContainer, Win11 24H2+ 특정 업데이트), CLI 기본 꺼짐·auto 모드에서 켜짐 | 있음(`mxc`/`elevated`/`unelevated`) |
| 전부 자동 승인 | `--dangerously-skip-permissions` | `--dangerously-skip-permissions` | `--dangerously-bypass-approvals-and-sandbox` (`--yolo`) |

## 1. Windows 설치와 로그인

### Claude Code

- 네이티브 설치: PowerShell 은 `irm https://claude.ai/install.ps1 | iex`, CMD 는 `curl -fsSL https://claude.ai/install.cmd -o install.cmd && install.cmd && del install.cmd` 이다. 관리자 권한은 필요 없다("You do not need to run as Administrator"). 설치 뒤 새 터미널을 열어 `claude --version` 으로 확인하고, `claude` 를 못 찾으면 PATH 문제로 안내한다. 네이티브 설치는 백그라운드 자동 업데이트를 한다. — <https://code.claude.com/docs/en/setup>
- winget: `winget install Anthropic.ClaudeCode`. winget 설치는 자동 업데이트하지 않는다(`winget upgrade Anthropic.ClaudeCode`). npm(`npm install -g @anthropic-ai/claude-code@latest`, Node.js 22+)도 있다. — 같은 문서
- Git for Windows 는 선택이다. 있으면 Bash 도구가 Git Bash 를 쓰고, 없으면 PowerShell 도구로 명령을 돌린다. PowerShell 도구는 `pwsh.exe`(7+)를 먼저 찾고 없으면 `powershell.exe`(5.1)로 넘어간다. — <https://code.claude.com/docs/en/setup>, <https://code.claude.com/docs/en/tools-reference>
- 로그인: Pro·Max·Team·Enterprise·Console 계정이 필요하다. `claude` 를 실행해 브라우저 안내를 따른다. `ANTHROPIC_API_KEY` 를 두고 사용을 승인하면 로그인 화면을 건너뛴다. — <https://code.claude.com/docs/en/setup>
- 새 PC 에서 git·pwsh 만 있을 때 가장 짧은 경로: `irm https://claude.ai/install.ps1 | iex` → 새 터미널 → `claude` → 브라우저 로그인. **[추론]** git 이 있으면 Git Bash 도 같이 깔렸으므로 Bash 도구까지 쓸 수 있다.

### Antigravity CLI (agy)

- 설치: PowerShell 은 `irm https://antigravity.google/cli/install.ps1 | iex`, CMD 는 `curl -fsSL https://antigravity.google/cli/install.cmd -o install.cmd && install.cmd && del install.cmd` 이다. 바이너리는 `C:\Users\<username>\AppData\Local\agy\bin` 에 놓인다. 설치 뒤 `agy --version` 으로 확인한다. — <https://antigravity.google/docs/getting-started?tab=cli>
- 설치 스크립트에 `--skip-aliases`·`--skip-path` 플래그가 있다. — <https://antigravity.google/docs/install?tab=cli>. **[추론]** 기본은 PATH 를 등록한다는 뜻이지만 문서가 직접 말하지는 않는다.
- 첫 실행 때 색 구성, 렌더링 모드(Alt-Screen/Inline), 저장소 폴더 신뢰 여부를 묻는다. — <https://antigravity.google/docs/getting-started?tab=cli>
- 로그인: OS 키링의 저장된 자격을 재사용하고, 없으면 브라우저를 연다. 원격 SSH 에서는 인증 URL 을 출력하고 받은 코드를 터미널에 붙여 넣는다. API 키는 `~/.gemini/antigravity-cli/settings.json` 에 `"modelProvider": "gemini"` 를 두고 `GEMINI_API_KEY` 를 export 해야 하며, `GEMINI_API_KEY` 만으로는 효과가 없다. ADC(`gcloud auth application-default login`) + `AGY_ADC_AUTH=true` 도 된다. 로그아웃은 `/logout`. — <https://antigravity.google/docs/install?tab=cli>
- winget: **[확인 못 함]** 공식 Antigravity 문서에는 없다. Flutter 문서(`docs.flutter.dev/ai/antigravity-cli`)가 `winget install Google.AntigravityCLI` 와 다른 스크립트 URL(`antigravity.google/install.ps1`)을 적고 있으나 Google Antigravity 1차 문서와 맞춰 보지 못했다. Chocolatey `antigravity-cli` 는 비공식 커뮤니티 패키지다.

### Codex CLI

- 설치: Windows 는 `powershell -ExecutionPolicy ByPass -c "irm https://chatgpt.com/codex/install.ps1 | iex"`, 또는 `npm install -g @openai/codex` 이다. — <https://github.com/openai/codex> (README)
- winget: **[확인 못 함]** 공식 문서에 CLI 용 winget 경로가 없다. 공식 Windows 앱 문서의 `winget install Codex -s msstore` 는 데스크톱 앱이다(검색 결과로만 봤고 CLI 와 구분해야 한다). `OpenAI.Codex` winget ID 는 제3자 글에서만 봤다.
- Windows 쪽 선행 조건으로 winget 이 있어야 한다고 적는다. — <https://learn.chatgpt.com/docs/windows/windows-sandbox>
- 로그인: `codex login`(브라우저, 기본), `codex login --device-auth`(장치 코드, 베타, headless·원격용), `printenv OPENAI_API_KEY | codex login --with-api-key`(stdin 으로 키 전달), `codex login status`, `codex logout`. 자격 저장 위치는 `cli_auth_credentials_store`(`file`=`~/.codex/auth.json`, `keyring`, `auto`, `ephemeral`)로 정한다. — <https://learn.chatgpt.com/docs/auth>
- 처음 `codex` 를 실행하면 "Sign in with ChatGPT" 등을 고른다. — <https://learn.chatgpt.com/docs/codex/cli>

## 2. 프로젝트 지시문 파일과 시작 방법, 비대화형 실행

### Claude Code

- 지시문 파일: `CLAUDE.md` 를 읽는다. 작업 폴더나 그 위에 `CLAUDE.md`·`CLAUDE.local.md` 가 없고 `AGENTS.md` 만 있으면 `AGENTS.md` 를 읽는다. 둘 다 있으면 `CLAUDE.md` 만 읽으며, `CLAUDE.md` 에서 `AGENTS.md` 를 import 하면 함께 들어간다. — <https://code.claude.com/docs/en/memory>
- 시작: `claude "query"` 는 첫 프롬프트를 넣은 대화형 세션이다(예: `claude "docs/setup/README.md 를 읽고 그대로 진행해"`). `--append-system-prompt-file <file>` 로 파일 내용을 시스템 프롬프트에 덧붙일 수도 있다. — <https://code.claude.com/docs/en/cli-reference>
- 비대화형: `claude -p "..."`. 성공 시 종료 코드 0. `--output-format json|stream-json` 지원. `-p` 실행은 따로 지정하지 않으면 Manual(`default`) 모드로 시작하고, 승인이 필요한 호출은 hook 이나 `--permission-prompt-tool` 이 없으면 거부된다. `--bare` 는 CLAUDE.md·hook·플러그인 탐색을 건너뛰고 OAuth 를 읽지 않으므로 `ANTHROPIC_API_KEY` 가 필요하다. — <https://code.claude.com/docs/en/headless>

### Antigravity CLI (agy)

- 지시문 파일: 작업 폴더와 그 위(저장소 루트까지)의 `AGENTS.md` 또는 `GEMINI.md`, `.agents/AGENTS.md` 또는 `.agents/GEMINI.md`, `.agents/rules/*.md`(frontmatter `trigger` 필요)를 읽는다. 전역은 `~/.gemini/AGENTS.md`·`~/.gemini/GEMINI.md` 등이다. 규칙은 교체가 아니라 누적된다. `AGENTS.md`·`GEMINI.md` 는 항상 켜진다. 규칙 파일 하나는 24,000 바이트 상한이다. — <https://antigravity.google/docs/rules>
- 시작: `agy -i "..."`(`--prompt-interactive`)가 첫 프롬프트로 대화형을 시작한다. 위치 인자 방식은 문서에 없다. — <https://antigravity.google/docs/cli/reference>, 로컬 `agy --help`(1.5.13)
- 비대화형: `agy -p "..."`(`--print`·`--prompt`), `--output-format text|json|stream-json`, `--print-timeout`. 승인을 얻을 수 없는 동작은 **soft-deny** 된다: 실행은 계속되고 종료 코드는 0 이며 stderr 에 알림만 남는다. `agentMode` 가 없으면 `-p` 는 가능할 때 `auto` 모드로 돈다. — <https://antigravity.google/docs/cli/headless>
- **[추론]** soft-deny + 종료 코드 0 이므로, 셋업 스크립트가 agy 의 종료 코드만 보고 성공을 판단하면 설치 단계가 조용히 빠질 수 있다. 결과 검증(예: `winget list`, `Get-Command`)을 지시문에 넣어야 한다.

### Codex CLI

- 지시문 파일: 전역(`~/.codex` 또는 `CODEX_HOME`)에서 `AGENTS.override.md`, 없으면 `AGENTS.md` 하나. 프로젝트는 Git 루트부터 현재 폴더까지 내려가며 폴더마다 `AGENTS.override.md` → `AGENTS.md` → `project_doc_fallback_filenames` 순으로 하나씩 읽고 이어 붙인다. 합계 상한 `project_doc_max_bytes` 기본 32 KiB. 실행(또는 TUI 세션)마다 한 번 만든다. — <https://learn.chatgpt.com/docs/agent-configuration/agents-md>
- **[추론]** `GEMINI.md`·`CLAUDE.md` 는 `project_doc_fallback_filenames` 에 넣지 않으면 읽지 않는다. 세 도구가 모두 읽는 공통 파일은 `AGENTS.md` 다(Claude Code 는 `CLAUDE.md` 가 없을 때, 또는 import 할 때).
- 시작: 최상위 `codex` 가 선택적 `PROMPT` 위치 인자를 받는다("Optional text instruction to start the session"). — <https://learn.chatgpt.com/docs/developer-commands?surface=cli>
- 비대화형: `codex exec "..."`, 프롬프트를 빼거나 `-` 를 주면 stdin 에서 읽는다(`cat prompt.txt | codex exec -`). 기본은 **read-only 샌드박스**이며 수정하려면 `--sandbox workspace-write` 가 필요하다. `--full-auto` 는 더 이상 지원하지 않고 `--sandbox workspace-write` 또는 `--approve-for-me` 로 바꾼다. Git 저장소가 아니면 `--skip-git-repo-check` 가 필요하다. 인증은 저장된 CLI 인증을 재사용하고, 한 번만 `CODEX_API_KEY` 를 줄 수도 있다. — <https://learn.chatgpt.com/docs/non-interactive-mode>. 로컬 `codex exec --help`(0.159.3)에도 `--full-auto` 는 없다.
- **[확인 못 함]** `codex exec` 가 AGENTS.md 를 읽는지 명시한 문장은 찾지 못했다. AGENTS.md 문서가 "once per run" 이라 하므로 읽는다고 보는 것이 자연스럽지만 문서 문장으로 확인하지는 못했다.

## 3. 명령 승인·권한 모드와 샌드박스가 설치 명령을 막는지

### Claude Code

- 모드: `default`(Manual: 작업 폴더 안 읽기만 자동), `acceptEdits`(파일 수정과 `mkdir`·`mv`·`cp` 등 흔한 파일 명령), `plan`, `auto`(분류기가 각 동작을 검토, force push·운영 배포·`curl | bash` 같은 것을 막는다), `dontAsk`(허용 규칙 밖은 자동 거부), `bypassPermissions`(전부 허용, 격리된 컨테이너·VM 용). `--dangerously-skip-permissions` 는 `--permission-mode bypassPermissions` 와 같다. — <https://code.claude.com/docs/en/permission-modes>, <https://code.claude.com/docs/en/cli-reference>
- 대화형 터미널 세션의 기본 시작 모드는 auto 이고, `-p` 와 Agent SDK 는 `default` 로 시작한다. — <https://code.claude.com/docs/en/permission-modes>
- Windows 특이점: `acceptEdits` 에서 PowerShell `Set-Content`·`Remove-Item` 등도 범위 안 경로면 자동 승인한다. "could not fully check your permission rules" 로 표시된 PowerShell 명령은 어느 모드에서도 자동 승인되지 않는다. 드라이브 루트·`C:\Windows`·홈 폴더 같은 critical path 삭제는 계속 묻는다. — <https://code.claude.com/docs/en/permission-modes>
- 샌드박스: **네이티브 Windows 는 지원하지 않는다**(macOS·Linux·WSL2 만). 기본도 꺼져 있다. 그래서 네이티브 Windows 에서는 명령이 샌드박스 없이 사용자 권한으로 돈다. — <https://code.claude.com/docs/en/sandboxing>, <https://code.claude.com/docs/en/setup>
- 설치 명령을 막는가: 샌드박스가 막지는 않는다. 막는 것은 권한 모드다. `-p` 의 Manual 모드에서는 `winget install` 같은 명령도 `--allowedTools "Bash(winget install *)"` 같은 허용 규칙이 없으면 거부된다. — <https://code.claude.com/docs/en/headless>. **[확인 못 함]** auto 모드 분류기가 `irm ... | iex` 를 `curl | bash` 처럼 막는지는 문서에 없다.
- 환경 변수는 명령 사이에 유지되지 않는다(`export` 가 다음 명령에 안 넘어간다). PowerShell 도구는 프로필을 읽지 않는다. 자식 프로세스가 stdin 을 기다리면 멈추지 않고 EOF 를 받는다. — <https://code.claude.com/docs/en/tools-reference>
- **[추론]** 설치 프로그램이 레지스트리의 사용자 PATH 를 바꿔도, 이미 떠 있는 Claude Code 프로세스에서 나오는 셸은 예전 PATH 를 물려받을 수 있다. 지시문에서 설치 뒤 `$env:Path` 를 레지스트리 값으로 다시 읽거나 전체 경로로 실행하게 해야 할 수 있다. 실측으로 확인해야 한다.

### Antigravity CLI (agy)

- 모드: `auto`(가능하면 기본, 명령을 터미널 샌드박스 안에서 돌리고 샌드박스를 벗어나야 하는 명령은 자동 평가해 안전·되돌릴 수 있는 것만 바로 실행), `accept-edits`, `default`(파일 diff 검토 + `toolPermission`, 기본 `request-review`). `toolPermission` 의 `strict`·`always-proceed`(`--dangerously-skip-permissions`)는 auto 모드보다 우선한다. 허용·거부 규칙은 `~/.gemini/antigravity-cli/settings.json` 의 `permissions.allow/deny/ask`(`command(git)`, `command(regex:...)`), 우선순위 Deny > Ask > Allow. auto 모드는 business·enterprise 계정에서 쓸 수 없다. Windows 에서 auto 모드는 v1.4.4 이상이 필요하고, PowerShell·CMD 에서 단어로 깔끔히 나눠지지 않는 명령은 정확히 일치해야 하므로 `command(regex:git .*)` 같은 정규식을 쓴다. — <https://antigravity.google/docs/permissions>
- 샌드박스: Windows CLI 는 AppContainer 기반으로 지원하며 "Windows 11 24H2 or later with the August 2026 update or later" 가 필요하다. CLI 의 `enableTerminalSandbox` 기본값은 `false` 지만 auto 모드가 켠다. 샌드박스 안 명령은 기본적으로 네트워크가 없고, Windows 에서는 사용자 프로필 밖 폴더는 읽기만 된다. `~/.ssh`·`.env` 는 막힌다. 샌드박스를 못 쓰는 기기에서는 `--sandbox` 가 효과가 없다. — <https://antigravity.google/docs/sandbox>, <https://antigravity.google/docs/cli/reference>
- 설치 명령을 막는가: **[추론]** auto 모드에서는 샌드박스에 네트워크가 없으므로 `winget`·`scoop`·`irm | iex` 는 샌드박스 안에서 실패하거나 샌드박스 밖 실행으로 넘어가 자동 평가를 받는다. Program Files 같은 사용자 프로필 밖 쓰기도 막힌다. headless 에서는 승인 못 받은 것이 soft-deny 된다. 무인 셋업이면 `command(winget)` 같은 allow 규칙이나 `--dangerously-skip-permissions` 가 필요하다.

### Codex CLI

- 샌드박스 모드: `read-only`, `workspace-write`(작업 폴더 읽기·쓰기·명령), `danger-full-access`(샌드박스 없음, 별칭 `--yolo`). 승인 정책: `on-request`(샌드박스 밖 동작, 예컨대 작업 폴더 밖 수정이나 네트워크 사용 전에 묻는다), `never`(묻지 않지만 샌드박스 안에서만 돈다), granular. `untrusted` 는 폐기되어 설정에 있으면 시작을 막을 수 있다. — <https://learn.chatgpt.com/docs/agent-approvals-security>
- `workspace-write` 에서 **네트워크는 기본 꺼짐**이며 `[sandbox_workspace_write] network_access = true` 로 켠다. — 같은 문서
- 플래그: `--sandbox/-s`, `--ask-for-approval/-a on-request|never`, `--approve-for-me`(자동 검토 + workspace-write), `--dangerously-bypass-approvals-and-sandbox`(`--yolo`, "Only use inside an externally hardened environment"), `--add-dir`. — <https://learn.chatgpt.com/docs/developer-commands?surface=cli>
- Windows 샌드박스: `mxc`(권장, 관리자 설정 불필요, Windows 11 24H2 build 26100.9278 / 25H2 build 26200.9278 이상), `elevated`(레거시 대안, 관리자가 승인한 설정 1회 필요, 전용 저권한 샌드박스 사용자·파일 권한 경계·방화벽 규칙), `unelevated`(레거시, 내 계정의 restricted token + ACL, 네트워크 격리가 약함). 설정은 `[windows] sandbox = "elevated"` 등과 `[features] prefer_mxc = true`. MXC 가능 여부 확인 명령은 CLI 0.162.0 이상이 필요하다. — <https://learn.chatgpt.com/docs/windows/windows-sandbox>
- 설치 명령을 막는가: 막는다. `codex exec` 기본은 read-only, `workspace-write` 도 네트워크가 꺼져 있어 `winget`·`scoop`·`irm | iex` 는 샌드박스 안에서 실패한다. 대화형이면 `on-request` 승인으로 샌드박스 밖 실행을 허락하고, 무인 실행이면 `--sandbox danger-full-access` 나 `--yolo` 가 필요하다. — 위 두 문서. **[추론]** 작업 폴더 밖(`%LOCALAPPDATA%`, `~\scoop`)에 쓰는 설치도 `workspace-write` 에서는 막힌다.

## 4. 관리자 권한 명령을 일반 권한 세션에서 실행하는 방법

### Windows 쪽 사실

- Sudo for Windows: Windows 11 24H2 이상, 설정 > 시스템 > 고급에서 켠다. 모드는 `forceNewWindow`(기본, 새 창에서 실행), `disableInput`(현재 창, 입력 핸들 닫힘), `normal`(인라인, 현재 창 입력 가능). 설정 변경은 관리자 콘솔에서 `sudo config --enable <mode>`. sudo 는 **UAC 로만** 승격하며 실행 때마다 확인 창이 뜬다. `disableInput`·`normal` 은 비권한 프로세스가 승격된 프로세스를 조종할 수 있는 위험이 있다. — <https://learn.microsoft.com/en-us/windows/advanced-settings/sudo/>
- gsudo: `winget install gerardog.gsudo`, `scoop install gsudo`, `choco install gsudo`. 기본은 승격 때마다 UAC 창이 한 번 뜬다. `gsudo cache on` 으로 캐시 세션을 열면(기본 5분 유휴 만료) 이후 승격은 UAC 없이 된다. 이미 승격된 콘솔에서는 UAC 가 안 뜬다. stdout·stderr 를 파이프·캡처할 수 있고 종료 코드를 그대로 넘기며, 승격 실패 시 종료 코드 999. 캐시는 악성 프로세스가 UAC 없이 승격할 수 있는 위험이 있다. — <https://github.com/gerardog/gsudo>
- **[추론]** Windows sudo 기본 `forceNewWindow` 는 출력이 새 창에 나오므로 에이전트가 결과를 읽지 못한다. 에이전트가 결과를 봐야 하면 `disableInput`(sudo) 또는 gsudo 가 맞다. 어느 쪽이든 UAC 창은 데스크톱에 뜨므로 사람이 앞에 있어야 한다.

### 도구별 동작

- Claude Code: 네이티브 Windows 에서 명령은 샌드박스 없이 Claude Code 프로세스와 같은 권한으로 돈다. `bypassPermissions` 의 root/sudo 거부 검사는 Linux·macOS 에만 적용되고 Windows 에는 적용되지 않는다. — <https://code.claude.com/docs/en/permission-modes>. 자식 프로세스가 stdin 을 기다리면 EOF 를 받는다. — <https://code.claude.com/docs/en/tools-reference>. **[확인 못 함]** `sudo`·`gsudo`·UAC 를 Claude Code 안에서 쓸 때의 동작을 적은 공식 문서는 찾지 못했다.
- agy: **[확인 못 함]** 공식 문서에 Windows 승격(UAC·sudo·gsudo)에 관한 내용이 없다. 권한 문서 예시에 `"deny": ["command(sudo)"]` 가 있을 뿐이다. — <https://antigravity.google/docs/permissions>. **[추론]** AppContainer 샌드박스 안에서는 승격이 불가능할 것이므로, 승격 명령은 샌드박스 밖 실행(승인 또는 `--dangerously-skip-permissions`)이 전제다.
- Codex: `elevated` 샌드박스에서도 샌드박스 명령은 관리자 권한 없이 돈다. 승인 정책이 더 많은 권한을 언제 물을지 정하고, 특정 예외는 rules 로 둔다. — <https://learn.chatgpt.com/docs/windows/windows-sandbox>. **[확인 못 함]** 샌드박스 밖(`danger-full-access`)에서 `sudo`·`gsudo` 를 부를 때의 동작은 문서에 없다.

### 남은 실측 과제

1. 세 도구 각각에서 `gsudo <명령>` 과 `sudo <명령>`(`disableInput`) 을 실행해 UAC 창이 뜨는지, 출력·종료 코드를 에이전트가 읽는지 확인한다.
2. 설치가 사용자 PATH 를 바꾼 뒤 같은 세션의 다음 명령이 새 PATH 를 보는지 확인한다.
3. Claude Code auto 모드가 `irm ... | iex` 를 막는지, Codex `on-request` 가 `winget install` 에 승인을 묻는지, agy auto 모드가 `winget install` 을 어떻게 평가하는지 확인한다.
4. 또 다른 길: 사람이 처음부터 관리자 터미널에서 에이전트를 띄우면 승격 문제가 사라진다. **[추론]** 대신 에이전트의 모든 명령이 관리자 권한으로 돌므로 권한 모드·샌드박스의 의미가 커진다(Claude Code 는 Windows 에 샌드박스가 없다).
