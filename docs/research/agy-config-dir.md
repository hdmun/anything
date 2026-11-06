# agy(Antigravity CLI) 설정·인증 위치와 계정별 분리 가능성

이슈: hdmun/anything#32 · 조사일 2026-11-06 · 대상 agy 1.5.1 (Windows 11, `C:\Users\hdmun\AppData\Local\agy\bin\agy.EXE`)

공개 1차 문서(공식 docs)에서는 저장 위치나 재지정 방법을 찾지 못했다. 그래서 아래 근거는 모두 로컬 1차 자료다: `agy --help`, `agy changelog`, 바이너리 문자열, `cli.log`, Windows 자격 증명 관리자(`cmdkey /list`), 실제 재현 실험.

## 결론

- **인증 토큰은 파일이 아니라 Windows 자격 증명 관리자에 저장된다.** 대상 이름은 `LegacyGeneric:target=gemini:antigravity`, 사용자는 `antigravity` 하나로 고정돼 있다. 이 항목은 Windows 로그온 사용자 단위로 관리되므로, 홈 디렉터리를 바꿔도 따라 바뀌지 않는다.
- **설정과 데이터는 `%USERPROFILE%\.gemini\` 아래에 있다** (`antigravity-cli\`, `config\`). `USERPROFILE`/`HOME`을 바꾸면 이 위치는 옮겨진다.
- **Google 로그인 계정을 계정별로 나누는 공식 env var나 플래그는 없다.** `--help`에는 config/data 디렉터리 플래그가 없다.
- 그래서 **`USERPROFILE`만 바꿔서는 계정이 나뉘지 않는다.** 실험해 보니 새 홈에서도 기존 계정으로 바로 인증됐다.

## 저장 위치 (근거)

| 항목 | 위치 | 근거 |
|---|---|---|
| OAuth 토큰 | 자격 증명 관리자 `gemini:antigravity` | `cmdkey /list`, `cli.log`의 `keyringAuth: loaded token` / `ChainedAuth: authenticated via keyring` |
| CLI 앱 데이터 (대화, brain, 로그, settings.json) | `%USERPROFILE%\.gemini\antigravity-cli\` | 디렉터리 내용, `cli.log`의 `AppDataDir` |
| 공용 설정 (mcp_config, hooks, skills, plugins) | `%USERPROFILE%\.gemini\config\` | 디렉터리 내용, 로그의 migration marker 경로 |
| IDE 데이터 | `%USERPROFILE%\.gemini\antigravity\`, `%USERPROFILE%\.antigravity\` | 디렉터리 내용 (CLI와 별개) |
| 실행 파일·업데이터 | `%LOCALAPPDATA%\agy\` | `where agy` |
| `%APPDATA%\Antigravity` | `.updaterId`만 있음 | 디렉터리 내용 |
| 시스템 키체인 한도를 넘는 큰 토큰 | CLI의 private secrets 파일 | changelog: "such tokens are now stored in the CLI's private secrets file" |

`.gemini\oauth_creds.json`과 `google_accounts.json`은 Gemini CLI가 쓰는 파일이다. agy 로그를 보면 이 파일이 아니라 keyring에서 토큰을 읽었다.

## 재현 실험

`USERPROFILE`과 `HOME`을 빈 임시 폴더로 바꾼 뒤 `agy models`를 실행했다.

- 결과: exit 0이고 모델 목록이 정상으로 나왔다.
- 임시 폴더 아래에 `.gemini\antigravity-cli\`와 `.gemini\config\`가 새로 생겼다. 즉 설정이 빈 상태에서 시작한다.
- 새로 생긴 `cli.log`에 `keyringAuth: loaded token ... ChainedAuth: authenticated via keyring`가 찍혔다. 기존과 같은 자격 증명 항목을 읽었다는 뜻이다.

## 계정 분리에 쓸 만한 수단

| 수단 | 계정 분리 | 근거·비고 |
|---|---|---|
| `USERPROFILE`/`HOME` 재지정 | 안 됨 | 데이터만 분리되고 토큰은 공유된다. 게다가 이 상태에서 로그인하면 공용 `gemini:antigravity` 항목을 **덮어쓴다**. 그러면 다른 세션의 계정도 함께 바뀐다. |
| `--settings` | 안 됨 | 세션에서만 쓰이는 settings.json 키다. 인증과는 관계없다. |
| `AGY_ADC_AUTH` | 됨 (Business/GCP 한정) | Application Default Credentials로 로그인한다. 프로세스마다 ADC 자격(`GOOGLE_APPLICATION_CREDENTIALS` 등)을 다르게 주면 나눌 수 있다. 개인 Google 계정이나 소비자 요금제에는 맞지 않고, Remote Control도 지원하지 않는다 (changelog). |
| `GEMINI_API_KEY` | 됨 (API 키 과금) | env var 하나로 프로세스별 분리가 된다. 다만 구독 할당량이 아니라 Gemini API로 과금된다. |
| `AGY_ACCOUNT` | 미확인 (가능성 낮음) | 바이너리 메시지는 `AGY_ACCOUNT=%q matches no signed-in account ... connect an account in the Plugins Manager`다. 메인 Google 로그인이 아니라 Plugins Manager에 연결한 계정을 고르는 용도로 보인다. |
| 숨은 플래그 `--app_data_dir=`, `--cli_dir_name=` | 안 됨 (데이터만) | 바이너리 문자열에만 있고 `--help`에는 없다. 내부 language server용으로 보인다. 동작하더라도 keyring 항목은 그대로 고정이다. |
| keyring 대신 파일에 토큰 저장 | 이론상 됨 (켜는 조건 미확인) | 바이너리 문자열: `Using file-based token storage because %s detected`, `OS credential manager unavailable ... falling back to file-based secret storage`. 이 모드에서는 토큰이 앱 데이터 디렉터리에 저장되므로, `USERPROFILE` 분리와 함께 쓰면 계정이 나뉠 수 있다. 다만 Windows에서 이 모드를 켜는 공식 스위치는 찾지 못했다. 확인된 것은 자동 전환뿐이다 (Linux에서 D-Bus가 없을 때, keyring timeout이 났을 때). |
| 별도 Windows 사용자 계정 (`runas`) | 됨 | 자격 증명 관리자는 Windows 사용자마다 따로 있으므로 확실히 나뉜다. 대신 무겁다. 파일 권한, Orca와 터미널 연동, 경로가 모두 달라진다. |

## USERPROFILE 재지정의 부작용

- `~/.gemini\config`에 있는 MCP·hooks·skills·plugins와 `antigravity-cli\settings.json`을 읽지 못한다. 복사하거나 링크해 둬야 한다.
- 대화 기록, `--continue`, projects 캐시가 계정별로 따로 생긴다.
- 첫 실행 때 migration이 돌고 `.migrated` marker가 만들어진다.
- 자식 프로세스(git, node, ssh 등)도 바뀐 홈을 본다. 그래서 `.gitconfig`, ssh 키, npm 캐시를 찾지 못할 수 있다.
- 토큰은 여전히 하나를 같이 쓴다. 한쪽에서 `/logout`하거나 다시 로그인하면 모든 세션이 영향을 받는다.

## 남은 질문

- Windows에서 파일 토큰 저장을 강제하는 env var가 있는가? 바이너리 문자열 `%s detected`의 `%s` 자리에 무엇이 들어가는지 확인해야 한다.
- `AGY_ACCOUNT`를 메인 로그인 선택에도 쓸 수 있는가? 계정 두 개로 로그인한 상태에서 시험해 봐야 한다.
