# claude·codex·agy 설정 디렉터리: 인증 파일 vs 공유 가능 파일 (Windows)

이슈: hdmun/anything#33 · 조사일 2026-11-06 · 로컬 확인 때는 파일 **이름만** 봤다(내용은 열지 않음).

## 결론 요약

| 도구 | 계정별로 분리할 것 (공유 금지) | 링크로 공유해도 되는 것 |
|---|---|---|
| Claude Code (`CLAUDE_CONFIG_DIR`) | `.credentials.json`, `.claude.json`(+`.tmp.*`), `sessions/`, `projects/`, `history.jsonl`, `daemon*`, `session-env/`, `shell-snapshots/`, `file-history/`, `tasks/`·`teams/`·`jobs/`, `stats-cache.json`, `mcp-needs-auth-cache.json`, `.last-*` | `CLAUDE.md`, `skills/`, `commands/`, `hooks/`(스크립트), `agents/`, `keybindings.json`, statusline 스크립트, (조건부) `settings.json`, `plugins/` |
| Codex CLI (`CODEX_HOME`) | `auth.json`, `auth*.lock`, `*.sqlite*`(state/goals/queue/memories/thread_history/logs), `sessions/`, `history.jsonl`, `session_index.jsonl`, `installation_id`, `cap_sid`, `.sandbox*`, `app-server-*`, `models_cache.json`, `log/`, `tmp/` | `AGENTS.md`, `skills/`, `hooks.json`, (조건부) `config.toml`, `plugins/`, `packages/` |
| agy (Antigravity CLI) | 설정 디렉터리 단위로 계정을 나누는 공식 방법이 없다 (3절 참고) | — |

## 1. Claude Code

- 문서: Windows에서는 자격 증명을 `%USERPROFILE%\.claude\.credentials.json`에 저장한다. `CLAUDE_CONFIG_DIR`를 설정하면 `.credentials.json`이 그 디렉터리 아래로 간다. 계정마다 디렉터리를 따로 두는 것이 공식 다중 계정 방식이다: "Each directory has its own settings, session history, and claude.ai login or API key." ([Authentication](https://code.claude.com/docs/en/iam), "Log in with multiple accounts"와 "Credential management" 절)
- 예외(문서): API 키 없이 로그인한 Console 계정은 설정 디렉터리 밖(Anthropic profile, Windows에서는 `%APPDATA%\Anthropic`)에 저장된다. 그래서 `CLAUDE_CONFIG_DIR`로는 분리되지 않는다. (같은 문서)
- `.claude.json` 위치(로컬 관찰): 기본 계정은 `~/.claude.json`(홈 루트)을 쓴다. 이미 쓰고 있는 `~/.claude-sub`에는 `.claude.json`과 `.claude.json.tmp.*`가 디렉터리 **안**에 있다. 즉 `CLAUDE_CONFIG_DIR`를 설정하면 `.claude.json`도 그 디렉터리 안으로 들어간다. 이 파일에는 계정 OAuth 메타데이터, 온보딩 상태, 프로젝트별 상태가 들어 있어 공유하면 안 된다.
- `settings.json` 자체는 계정 정보가 아니다. 다만 `env` 블록에 `CLAUDE_CODE_OAUTH_TOKEN`이나 `ANTHROPIC_API_KEY`를 넣어 두었다면 공유하는 순간 계정이 섞인다(문서 "Authentication precedence"). 공유하기 전에 확인해야 한다.
- 로컬 관찰: `~/.claude-sub/CLAUDE.md`와 `~/.claude-sub/skills`가 이미 `~/.claude`를 가리키는 **SymbolicLink**로 쓰이고 있다. 이 머신에서는 symlink 공유가 실제로 동작한다.

## 2. Codex CLI

- 문서: 로그인 정보는 `CODEX_HOME`(기본값 `~/.codex`) 아래의 평문 `auth.json`이나 OS 자격 증명 저장소에 저장된다. `cli_auth_credentials_store` 값은 `file | keyring | auto | ephemeral` 중 하나다. 문서는 `auth.json`을 비밀번호처럼 다루라고 한다. ([Codex Auth](https://learn.chatgpt.com/docs/auth))
- 로컬: `config.toml`에 `cli_auth_credentials_store`가 없고 `auth.json`이 있다. 지금은 file 방식으로 저장되고 있다는 뜻이다. **주의**: `keyring`이나 `auto`로 바꾸면 Windows Credential Manager에 저장된다. 이때 `CODEX_HOME`만으로 계정이 나뉘는지는 문서에 없어 보장할 수 없다(미확인). 여러 계정을 쓰려면 `file`로 고정하는 것을 권장한다.
- `config.toml`은 공유할 수 있다. 다만 계정에 따라 달라지는 설정(예: `forced_login_method`, `forced_chatgpt_workspace_id`, 프로바이더 키 env 참조)이 있으면 계정별로 둔다. sqlite, 세션, history는 계정별 스레드 상태다. 공유하면 잠금 충돌이나 스레드가 섞일 위험이 있다.

## 3. agy (Antigravity CLI)

- 로컬 관찰:
  - 상태: `~/.gemini/antigravity-cli/`(conversations, brain, history.jsonl, cache, log 등)
  - 설정: `~/.gemini/config/`(config.json, hooks.json, mcp_config.json, skills/, plugins/)
  - 그 밖: `~/.gemini/oauth_creds.json`·`google_accounts.json`(Gemini 계열 계정 파일), `~/.antigravitycli/<uuid>.json`
- `agy --help`에 설정 디렉터리를 지정하는 플래그가 없다. `--settings`는 그 세션에서만 쓰는 settings JSON일 뿐이다.
- 바이너리 문자열에 `ANTIGRAVITY_CONFIG_REL_DIR`, `ANTIGRAVITY_EXECUTABLE_DATA_DIR`가 보인다. 하지만 공개 문서가 없고 동작은 검증하지 않았다.
- `keyring`/`wincred` 문자열이 많이 나온다. 인증 정보를 Windows Credential Manager에 저장할 가능성이 높다(추정).
- 결론: 1차 출처로 확인된 "계정별 설정 디렉터리" 방식이 없다. agy 다중 계정은 지금은 이 방식으로 할 수 없다고 본다. 꼭 필요하면 별도 Windows 사용자나 API 키 기반 인증을 검토한다(#34에서 결정).

## 4. Windows 링크 동작

- 출처: [Hard Links and Junctions](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions)
  - junction은 **디렉터리 전용**이다. 같은 컴퓨터의 로컬 볼륨끼리만 된다(네트워크 드라이브와 파일은 안 됨).
  - hard link는 파일 전용이고 같은 볼륨 안에서만 된다.
- symbolic link는 파일과 디렉터리 모두 된다. 만들려면 `SeCreateSymbolicLinkPrivilege`가 필요하다. 개발자 모드가 켜져 있으면 관리자가 아니어도 만들 수 있다([Create symbolic links](https://learn.microsoft.com/en-us/windows/win32/fileio/creating-symbolic-links), `SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE`). 이 머신은 `AllowDevelopmentWithoutDevLicense=1`이라 개발자 모드가 켜져 있다.
- 권장:
  - 디렉터리(`skills/`, `commands/`, `hooks/`, `agents/`, `plugins/`): **junction**을 쓴다(`New-Item -ItemType Junction`). 별도 권한이 필요 없다.
  - 단일 파일(`CLAUDE.md`, `AGENTS.md`, `settings.json`, `config.toml`, `hooks.json`): **symlink**를 쓴다(개발자 모드 필요).
  - hard link는 쓰지 않는다. 도구가 임시 파일을 쓴 뒤 rename으로 바꿔치기하는 원자적 저장을 하면(`.claude.json.tmp.*`가 그 흔적) hard link가 끊기고, 두 파일이 아무 경고 없이 따로 바뀐다.
  - symlink도 rename 방식으로 저장하면 일반 파일로 바뀔 수 있다. 도구가 **자주 다시 쓰는 파일**(`/config`로 바뀌는 settings.json, trust 기록이 쌓이는 config.toml 등)은 공유하지 말고 복사하거나 주기적으로 동기화하는 방법도 고려한다.
  - Git Bash의 `ln -s`는 기본적으로 링크 대신 복사본을 만든다(`MSYS=winsymlinks:nativestrict`가 필요하다). PowerShell `New-Item`을 쓰는 것이 낫다.

## 미확인 / 후속

- Codex `keyring` 모드에서 `CODEX_HOME`마다 Credential Manager 항목이 따로 생기는지.
- agy 설정·인증 경로를 바꾸는 방법(공식 문서 없음).
- Claude Code와 Codex가 symlink로 연결된 `settings.json`/`config.toml`을 저장할 때 링크를 유지하는지 실측.
