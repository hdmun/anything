# 푸시 전 유출 검사 도구 비교

- 이슈: hdmun/anything#54 (상위 지도 #51)
- 조사일: 2026-11-09
- 범위: 공식 문서, 프로젝트 README·규칙 파일·소스 코드, 패키지 저장소(winget·scoop)를 읽었다. 도구를 설치하거나 실행하지 않았다. 그래서 "실제로 잡히는가"는 모두 규칙·소스를 읽고 판단한 것이다.
- 이 문서는 사실만 모은다. 어떤 도구를 언제·어디서 쓸지는 다음 티켓에서 정한다.
- 문서 안의 IP·이름·URL 은 모두 더미다(RFC 5737 주소, `<웹훅 ID>` 같은 자리 표시).

## 핵심 사실 먼저

- **디스코드 웹훅 URL 을 기본 규칙으로 잡는 것은 trufflehog 하나뿐이다.** gitleaks 기본 규칙(222개)과 GitHub 지원 패턴 목록에는 디스코드 웹훅 URL 이 없다. 디스코드는 봇 토큰·클라이언트 ID/시크릿만 있다.
- **IP·PC 이름 같은 "비밀이 아닌 개인 정보"를 잡는 기본 규칙은 네 후보 모두 없다.** 사용자 규칙으로 더할 수 있는 것은 gitleaks, trufflehog, 직접 쓴 훅이다. GitHub 사용자 지정 패턴은 조직 소유 저장소 전용이라 `hdmun/anything`(개인 계정 소유)에서는 쓸 수 없다.
- **PC 이름·계정 이름은 실제 값 목록이 있어야 잡힌다.** 그 목록을 공개 저장소의 규칙 파일에 넣으면 규칙 파일이 곧 유출이 된다. gitleaks·trufflehog 는 저장소 밖 설정 파일을 경로·환경 변수로 받을 수 있다.
- **로컬 훅은 `git push --no-verify` 로 완전히 건너뛸 수 있다.** GitHub push protection 은 서버에서 돌므로 이 옵션과 상관없다. 다만 저장소 쓰기 권한이 있는 사람은 사유를 대고 우회할 수 있고, REST API 로도 우회할 수 있다.
- **trufflehog 의 훅 모드는 "검증된 것·검증 실패한 것"만 보여 준다.** 검증 엔드포인트가 없는 사용자 규칙(IP·PC 이름)은 항상 "검증 안 됨"이므로 훅 모드 기본 설정에서는 보고되지 않는다(소스 확인).

## 출처

| 약칭 | URL |
| --- | --- |
| [gl-README] | https://github.com/gitleaks/gitleaks/blob/master/README.md (master `5f6ec56`, 2026-10-23) |
| [gl-toml] | https://github.com/gitleaks/gitleaks/blob/v8.30.1/config/gitleaks.toml |
| [gl-cmd-git] | https://github.com/gitleaks/gitleaks/blob/master/cmd/git.go |
| [gl-src-git] | https://github.com/gitleaks/gitleaks/blob/master/sources/git.go |
| [gl-hooks] | https://github.com/gitleaks/gitleaks/blob/master/.pre-commit-hooks.yaml |
| [gl-rel] | https://github.com/gitleaks/gitleaks/releases/tag/v8.30.1 (2026-03-21) |
| [th-README] | https://github.com/trufflesecurity/trufflehog/blob/main/README.md (main `f8221ca`, 2026-11-05) |
| [th-PreCommit] | https://github.com/trufflesecurity/trufflehog/blob/main/PreCommit.md |
| [th-custom] | https://github.com/trufflesecurity/trufflehog/blob/main/pkg/custom_detectors/CUSTOM_DETECTORS.md |
| [th-validation] | https://github.com/trufflesecurity/trufflehog/blob/main/pkg/custom_detectors/validation.go |
| [th-discord] | https://github.com/trufflesecurity/trufflehog/blob/main/pkg/detectors/discordwebhook/discordwebhook.go |
| [th-main] | https://github.com/trufflesecurity/trufflehog/blob/main/main.go |
| [th-engine] | https://github.com/trufflesecurity/trufflehog/blob/main/pkg/engine/engine.go |
| [th-rel] | https://github.com/trufflesecurity/trufflehog/releases/tag/v3.99.8 (2026-11-02) |
| [gh-pp] | https://docs.github.com/en/code-security/concepts/secret-security/push-protection |
| [gh-pp-cli] | https://docs.github.com/en/code-security/concepts/secret-security/command-line-push-protection |
| [gh-pp-cli-howto] | https://docs.github.com/en/code-security/how-tos/secure-your-secrets/work-with-leak-prevention/push-protection-on-the-command-line |
| [gh-scope] | https://docs.github.com/en/code-security/reference/secret-security/secret-scanning-scope |
| [gh-patterns] | https://docs.github.com/en/code-security/reference/secret-security/supported-secret-scanning-patterns , 데이터 원본: https://github.com/github/docs/blob/main/src/secret-scanning/data/pattern-docs/fpt/public-docs.yml |
| [gh-custom] | https://docs.github.com/en/code-security/how-tos/secure-your-secrets/customize-leak-detection/define-custom-patterns , 제공 범위 문구: https://github.com/github/docs/blob/main/data/reusables/gated-features/secret-scanning-custom-patterns.md |
| [gh-generic] | https://docs.github.com/en/code-security/how-tos/secure-your-secrets/detect-secret-leaks/enabling-secret-scanning-for-generic-patterns , 제공 범위 문구: https://github.com/github/docs/blob/main/data/reusables/gated-features/secret-scanning-non-provider-patterns.md |
| [gh-gated] | https://github.com/github/docs/blob/main/data/reusables/gated-features/secret-scanning.md |
| [gh-exclude] | https://docs.github.com/en/code-security/how-tos/secure-your-secrets/customize-leak-detection/exclude-folders-and-files |
| [gh-bypass] | https://github.com/github/docs/blob/main/data/reusables/secret-scanning/bypass-reasons-and-alerts.md , https://github.com/github/docs/blob/main/data/reusables/secret-scanning/push-protection-public-repos-bypass.md |
| [gh-rest] | https://docs.github.com/en/rest/secret-scanning/secret-scanning (Create a push protection bypass) |
| [githooks] | https://git-scm.com/docs/githooks#_pre_push (원본: https://github.com/git/git/blob/master/Documentation/githooks.adoc) |
| [git-push] | https://git-scm.com/docs/git-push#Documentation/git-push.txt---no-verify |
| [mingw.c] | https://github.com/git/git/blob/master/compat/mingw.c (`parse_interpreter`) |
| [discord-ref] | https://github.com/discord/discord-api-docs/blob/main/developers/reference.mdx (Base URL, API Versioning, Snowflakes) |
| [discord-wh] | https://github.com/discord/discord-api-docs/blob/main/developers/resources/webhook.mdx (Execute Webhook) |
| [rfc5737] | https://www.rfc-editor.org/rfc/rfc5737 |
| [rfc1918] | https://www.rfc-editor.org/rfc/rfc1918 |
| [scoop-gl] | https://github.com/ScoopInstaller/Main/blob/master/bucket/gitleaks.json |
| [scoop-th] | https://github.com/ScoopInstaller/Main/blob/master/bucket/trufflehog.json |
| [winget-gl] | https://github.com/microsoft/winget-pkgs/tree/master/manifests/g/Gitleaks/Gitleaks |

표기:

- **사실**: 위 출처에 쓰여 있거나 소스 코드에서 읽은 것.
- **추론**: 사실에서 끌어낸 판단. 실행해서 확인하지 않았다.
- **미확인**: 출처를 찾지 못했거나 실행해야만 알 수 있는 것.

---

## 비교표

| 질문 | gitleaks | trufflehog | GitHub push protection | 직접 쓴 pre-push 훅 |
| --- | --- | --- | --- | --- |
| 디스코드 웹훅 URL 기본 탐지 | 없음. 디스코드 규칙은 API 토큰·클라이언트 ID·클라이언트 시크릿 3개뿐 | 있음. `discordwebhook` 탐지기. 단 `https://discord.com/api/webhooks/` 형태만 | 없음. 디스코드는 Bot Token 하나 | 직접 정규식을 쓰면 됨 |
| 비밀 아닌 값(IP·PC 이름) 사용자 규칙 | 됨. `[[rules]]` 에 정규식. 키워드는 선택 | 됨(알파 기능). 정규식 + 키워드 1개 이상 필수 | 이 저장소에서는 안 됨. 사용자 지정 패턴은 조직 소유 저장소 전용 | 됨. 무엇이든 |
| 더미 허용 목록 | 됨. `[[allowlists]]` 의 `regexes`·`stopwords`·`paths`, 줄 주석 `gitleaks:allow`, `.gitleaksignore` 지문 | 부분. 사용자 규칙의 `exclude_regexes_match`·`exclude_words`, 줄 주석 `trufflehog:ignore`, `--exclude-paths`. 기본 탐지기에 값 단위 허용 목록은 못 찾음 | 경로 단위만. `.github/secret_scanning.yml` 의 `paths-ignore`. 값 단위는 없음 | 됨. 무엇이든 |
| Windows 실행 | Windows x64·x32·arm64 zip 배포 | Windows amd64·arm64 tar.gz 배포 | 서버에서 돎. 로컬 무관 | Git for Windows 가 셔뱅을 읽어 `sh` 로 실행 |
| winget | `Gitleaks.Gitleaks` 8.30.1 | 없음(`winget search trufflehog` 결과 없음) | 해당 없음 | 해당 없음(Git 만 있으면 됨) |
| scoop | `main/gitleaks` 8.30.1 | `main/trufflehog` 3.99.8 | 해당 없음 | 해당 없음 |
| 오탐 처리 | 허용 목록, `gitleaks:allow`, `.gitleaksignore`, 기준선 보고서(`--baseline-path`), 규칙 끄기(`disabledRules`) | `--results=verified` 로 검증된 것만, `trufflehog:ignore`, `--exclude-detectors`, `--filter-entropy` | 웹에서 사유 선택 후 3시간 안에 다시 푸시, 또는 REST API 로 우회 | 직접 작성 |
| 로컬에서 건너뛰기 | 훅으로 부르면 `--no-verify` 로 건너뜀 | 같음 | 불가(서버 쪽) | `--no-verify` 로 건너뜀 |
| 라이선스 | MIT | AGPL-3.0 | 해당 없음 | 해당 없음 |

---

## 1. gitleaks

### 사실

- **기본 규칙**: v8.30.1 기본 설정에 규칙이 222개 있다. 디스코드 관련은 `discord-api-token`, `discord-client-id`, `discord-client-secret` 3개다. 웹훅 규칙은 `slack-webhook-url`, `microsoft-teams-webhook` 은 있고 디스코드 웹훅은 없다. IP 주소 규칙은 없다. [gl-toml]
- `discord-*` 규칙 3개는 모두 `discord` 라는 이름 뒤에 `=`·`:` 같은 대입 기호가 오고, 그 뒤에 16진수 64자·숫자 18자·영숫자 32자가 오는 형태를 찾는다. [gl-toml]
- **사용자 규칙**: `.gitleaks.toml` 에 `[[rules]]` 를 쓴다. 항목은 `id`, `regex`(Go 정규식, 전방 탐색 없음), `secretGroup`, `entropy`, `path`, `keywords`, `tags`. `keywords` 는 정규식 전 빠른 문자열 거르기용이고, 규칙에 있을 때만 쓰인다. [gl-README]
- `[extend] useDefault = true` 로 기본 규칙을 유지한 채 규칙을 더한다. `disabledRules` 로 기본 규칙을 끈다. `path = "..."` 로 다른 설정 파일을 이어받을 수 있다(깊이 2까지). [gl-README]
- **설정 파일 찾는 순서**: ① `--config/-c` ② 환경 변수 `GITLEAKS_CONFIG`(경로) ③ 환경 변수 `GITLEAKS_CONFIG_TOML`(내용) ④ 대상 경로의 `.gitleaks.toml`. 아무것도 없으면 기본 설정. [gl-README]
- **허용 목록**:
  - 규칙별 `[[rules.allowlists]]`, 전역 `[[allowlists]]`(v8.25.0 부터), 여러 규칙에 거는 `targetRules`. [gl-README]
  - 조건: `commits`, `paths`, `regexes`, `stopwords`. 기본은 하나만 맞아도(OR) 무시, `condition = "AND"` 도 된다. [gl-README]
  - `regexTarget`: `secret`(기본), `match`, `line`. `stopwords` 는 추출된 비밀 값만 본다. [gl-README]
  - 줄 끝 주석 `gitleaks:allow` 가 있으면 그 줄을 무시한다. `--ignore-gitleaks-allow` 로 이 주석을 무시할 수 있다. [gl-README]
  - `.gitleaksignore` 에 결과의 `Fingerprint` 를 넣으면 그 결과만 무시한다. 지문은 `커밋:파일:규칙:줄` 꼴이다. README 는 "실험 기능"이라고 쓴다. [gl-README]
  - `--baseline-path` 에 이전 보고서를 주면 새 결과만 낸다. [gl-README]
- **검사 범위**: `gitleaks git` 은 내부에서 `git log -p -U0` 을 돌린다. `--log-opts` 로 범위를 준다(예: `--log-opts="--all commitA..commitB"`). `--staged`(스테이징된 것), `--pre-commit`(`git diff` 로 검사) 플래그가 있다. [gl-README] [gl-cmd-git]
- 소스에서 검사 대상(`Fragment.Raw`)은 패치의 **추가된 줄**이다. 커밋 메시지는 `CommitInfo.Message` 메타데이터로만 담긴다. [gl-src-git]
- **훅**: 공식 훅은 pre-commit 용뿐이다. pre-commit 프레임워크 훅 `gitleaks`·`gitleaks-system` 이 `gitleaks git --pre-commit --redact --staged --verbose` 를 부른다. README 는 `.git/hooks/` 에 복사할 `pre-commit.py` 예제도 안내한다. pre-push 용 공식 훅은 못 찾았다. [gl-hooks] [gl-README]
- **출력·종료 코드**: `--redact` 로 로그·표준 출력에서 비밀을 가린다. 종료 코드 0 = 없음, 1 = 발견 또는 오류, 126 = 모르는 플래그. `--exit-code` 로 바꿀 수 있다. [gl-README]
- **설치**: 릴리스에 `windows_x64.zip`, `windows_x32.zip`, `windows_arm64.zip` 이 있다. [gl-rel] winget 에 `Gitleaks.Gitleaks` 8.30.1(게시자 Gitleaks LLC, MIT) [winget-gl], scoop `main` 버킷에 `gitleaks` 8.30.1 이 있다(`bin: gitleaks.exe`). [scoop-gl] (`winget search`·`scoop search` 로 2026-11-09 확인)

### 추론

- 디스코드 웹훅 URL 을 `WEBHOOK_URL=https://discord.com/api/webhooks/<웹훅 ID>/<토큰>` 처럼 써도 `discord-*` 규칙 3개와 `generic-api-key` 에 걸리지 않을 것으로 읽힌다. 값이 `https:` 로 시작해 각 규칙의 값 문자 집합(16진수·숫자·`[\w.=-]`)과 맞지 않기 때문이다. 실행해서 확인하지 않았다.
- 커밋 메시지에 든 IP·웹훅은 `gitleaks git` 으로 잡히지 않을 것으로 읽힌다(위 소스 사실). 실행해서 확인하지 않았다.
- pre-push 에서 쓰려면 훅 스크립트가 표준 입력의 `<원격 해시>..<로컬 해시>` 를 `--log-opts` 로 넘겨야 한다. 원격 브랜치가 아직 없을 때(원격 해시가 0)는 범위를 따로 정해야 한다.
- `.exe` 하나라 Git Bash·PowerShell 어디서든 돌 것이다. 내부에서 `git` 을 부르므로 `git` 이 PATH 에 있어야 한다.

### 미확인

- Git Bash 에서 실제로 돌려 본 결과.
- 디스코드 웹훅 URL·IP 가 실제로 안 잡히는지(위 추론)의 실행 확인.

---

## 2. trufflehog

### 사실

- **기본 탐지기**: README 는 "700개가 넘는 탐지기, 각 API 로 능동 검증"이라고 쓴다. [th-README]
- **디스코드 웹훅**: `discordwebhook` 탐지기가 있다. 키워드는 `https://discord.com/api/webhooks/`, 정규식은 `https://discord.com/api/webhooks/` + 숫자 18~19자 + `/` + `[0-9a-zA-Z-]` 68자다. 검증을 켜면 찾은 URL 에 **GET 요청을 보내** 2xx 면 "검증됨"으로 본다. [th-discord]
- 디스코드 봇 토큰 탐지기 `discordbottoken` 도 있다. IP 주소 자체를 찾는 탐지기는 목록에서 못 찾았다(`ipinfo`·`ipstack` 등은 그 서비스의 API 키 탐지기다). [th-README] (탐지기 디렉터리 목록 확인)
- **결과 상태**: `verified`(API 로 유효 확인), `unverified`(찾았지만 확인 못 함 또는 검증 꺼짐), `unknown`(검증 시도 중 오류). `--results` 기본값은 `verified,unverified,unknown`. [th-README]
- **사용자 규칙(Custom Regex Detector, 알파)**: `--config` 로 받는 YAML 의 `detectors:` 에 쓴다. 정규식과 **키워드 1개 이상이 필수**다. 키워드가 비면 설정 검증에서 `no keywords` 오류가 난다. [th-README] [th-validation]
- 사용자 규칙의 `verify`(웹훅 검증)는 선택이다. 없으면 모든 결과가 `unverified` 다. [th-custom]
- 사용자 규칙의 거르기: `exclude_regexes_capture`, `exclude_regexes_match`(전체 일치에 대한 제외 정규식), `exclude_words`(부분 문자열), `entropy`, `validations`(숫자·대소문자·특수 문자 포함 조건). [th-custom]
- **무시**: 줄 번호를 지원하는 소스에서 줄에 `trufflehog:ignore` 주석이 있으면 그 결과를 버린다. `git`·`filesystem` 소스는 줄 번호를 지원한다. `--no-ignore-tag` 로 주석을 무시할 수 있다. [th-README] [th-engine]
- `git` 하위 명령 플래그: `--since-commit`, `--branch`, `--max-depth`, `--bare`(pre-receive 용), `--include-paths`·`--exclude-paths`(정규식 목록 파일), `--exclude-globs`. 전역: `--fail`(발견 시 종료 코드 183), `--no-verification`, `--exclude-detectors`, `--filter-entropy`, `--no-update`(업데이트 확인 끄기). [th-main] [th-README]
- 로컬 저장소는 악성 git 설정 대비(CVE-2025-41390)로 임시 디렉터리에 복제한 뒤 검사한다. `--trust-local-git-config` 로 건너뛸 수 있다. [th-README]
- **훅 모드**: 환경 변수 `PRE_COMMIT=1`(pre-commit 프레임워크), `HUSKY=1`, `TRUFFLEHOG_PRE_COMMIT=1` 중 하나가 있으면 훅 모드가 된다. 훅 모드는 ① 스테이징된 변경만 검사(`HEAD..HEAD`), ② `--results=verified,unknown` 으로 덮어씀, ③ `--fail` 을 켠다. [th-main]
- 공식 훅 안내(PreCommit.md)는 pre-commit 예시와, pre-commit 프레임워크에서 `stages: ["pre-commit", "pre-push"]` 예시를 준다. 오탐 대처로 `--results=verified` 와 `trufflehog:ignore` 를 든다. [th-PreCommit]
- **설치**: 릴리스에 `windows_amd64.tar.gz`, `windows_arm64.tar.gz` 가 있다. [th-rel] PreCommit.md 는 설치 스크립트가 "Linux, macOS, Windows (WSL 포함)"용이라고 쓴다. [th-PreCommit] scoop `main` 버킷에 `trufflehog` 3.99.8 이 있다(`bin: trufflehog.exe`). [scoop-th] winget 에는 없다(`winget search trufflehog` 결과 없음, 2026-11-09).

### 추론

- 디스코드 웹훅 탐지기는 다음 형태를 놓칠 수 있다: 옛 도메인 `discordapp.com`, API 버전이 든 경로 `https://discord.com/api/v10/webhooks/...`, 숫자 20자 ID, 토큰에 `_` 가 든 경우. 근거: 디스코드 문서는 경로에 버전을 넣으라고 하고(`https://discord.com/api/v{version_number}`), ID 는 최대 64비트 snowflake 라고 쓴다 [discord-ref]. 토큰 문자 집합은 디스코드 문서에 없다(미확인).
- 훅 모드(`--results=verified,unknown`)에서는 `verify` 없는 사용자 규칙(IP·PC 이름) 결과가 `unverified` 라 보고되지 않는다. 사용자 규칙을 쓰려면 훅 모드 환경 변수 없이 `--results` 를 직접 줘야 한다.
- 훅 모드는 스테이징된 변경만 보므로, pre-commit 프레임워크로 pre-push 단계에서 돌리면(`PRE_COMMIT=1` 이 설정된다면) 푸시되는 커밋을 보지 않을 수 있다. pre-commit 프레임워크가 pre-push 단계에서도 `PRE_COMMIT=1` 을 넣는지는 미확인.
- 검증이 켜져 있으면 찾은 웹훅 URL 로 디스코드에 요청을 보낸다. 무인 파이프라인에서는 외부 네트워크 호출이 생긴다. `--no-verification` 을 주면 결과가 모두 `unverified` 가 된다.
- IP 정규식에 붙일 고정 키워드가 마땅치 않다(키워드 필수 조건).

### 미확인

- Git Bash 에서 실제로 돌려 본 결과.
- 커밋 메시지도 검사하는지.
- 기본 탐지기에 값 단위 허용 목록(예: 특정 더미 값 무시)이 있는지. 찾은 것은 줄 주석·경로 제외·탐지기 제외뿐이다.

---

## 3. GitHub secret scanning push protection

### 사실

- **두 종류**: [gh-pp]
  - 저장소 push protection: GitHub Secret Protection 이 켜져 있어야 하고, 기본은 꺼짐, 저장소 관리자가 켠다. 우회하면 알림(alert)을 만든다.
  - 사용자 push protection: GitHub.com 계정마다 적용, **기본 켜짐**, 공개 저장소로의 푸시를 막는다. 저장소 쪽이 꺼져 있으면 우회해도 알림이 없다.
- 공개 저장소에서 secret scanning 은 무료로 자동 실행된다. [gh-gated]
- **막는 종류**: 파트너 패턴(push protection 지원 패턴만), 일반 패턴, 사용자 지정 패턴, AI 로 찾은 일반 비밀(공개 미리 보기). [gh-pp] 파트너 패턴은 "가장 최신 토큰 버전"만 막는다. [gh-patterns]
- **디스코드**: 지원 패턴 목록의 디스코드 항목은 `discord_bot_token`(Discord Bot Token) 하나다. push protection 지원, 유효성 검사 지원. 디스코드 웹훅 URL 패턴은 없다. 웹훅 패턴은 Slack(Incoming·Workflow), Power Automate 등만 있다. IP 주소 패턴은 없다. [gh-patterns]
- **일반 패턴**(개인 키, DB 연결 문자열, HTTP Basic/Bearer 헤더 등): GitHub.com 에서는 "Team 요금제 조직 소유 저장소 + Secret Protection" 에서만 쓸 수 있다. [gh-generic]
- **사용자 지정 패턴**: "Team 또는 Enterprise 의 조직 소유 저장소 + Secret Protection" 에서만 쓸 수 있다. [gh-custom] push protection 본문도 "조직 저장소용"이라고 쓴다. [gh-pp]
- **경로 제외**: `.github/secret_scanning.yml` 의 `paths-ignore` 로 경로를 알림과 push protection 에서 뺀다. 1,000개 넘는 항목은 앞 1,000개만, 1 MB 넘는 파일은 통째로 무시한다. [gh-exclude] 값 단위 허용 목록은 문서에서 못 찾았다.
- **막혔을 때(명령줄)**: 푸시가 거부되고, 원격 메시지에 비밀이 든 커밋·경로가 나온다. 한 번에 최대 5개를 보여 준다. 이미 알림이 있는 비밀은 막지 않는다. [gh-pp-cli] [gh-pp-cli-howto]
- **우회**: 메시지의 URL 을 열어 사유(테스트용·오탐·나중에 고침)를 고르고 "Allow me to push this secret" 을 누른 뒤 **3시간 안에** 다시 푸시한다. [gh-pp-cli-howto] 사유별로 닫힌 알림 또는 열린 알림이 생긴다. [gh-bypass]
- **REST API 우회**: `POST /repos/{owner}/{repo}/secret-scanning/push-protection-bypasses` 에 `reason`(`false_positive`·`used_in_tests`·`will_fix_later`)과 `placeholder_id`(막힌 응답에 들어 있음)를 보낸다. 비밀을 커밋한 본인이어야 하고, 클래식 토큰은 `repo` 범위가 필요하다. [gh-rest]
- **한계**: 푸시가 너무 크면 시간 초과로 막지 못하고 푸시 뒤 검사한다. 공개 저장소에서 50 MB 넘는 푸시는 검사하지 않는다. 기존 비밀이 1,000개 넘게 든 푸시는 막지 않는다. [gh-scope]
- **이 저장소의 현재 설정**(`gh api repos/hdmun/anything`, 2026-11-09): 공개, 소유자 유형 `User`, `secret_scanning` 켜짐, `secret_scanning_push_protection` 켜짐, `secret_scanning_non_provider_patterns`(일반 패턴) 꺼짐, `secret_scanning_validity_checks` 꺼짐.

### 추론

- 이 저장소에서는 이미 push protection 이 켜져 있으므로 디스코드 봇 토큰 등 지원 패턴은 지금도 막힌다. IP·PC 이름·디스코드 웹훅 URL 은 막히지 않는다.
- 막히면 우회는 웹 화면이나 REST API 로만 된다. 무인 에이전트가 `repo` 범위 토큰을 갖고 있으면 API 로 스스로 우회할 수 있다.
- 서버에서 돌기 때문에 로컬 설치·Windows 설정과 상관없고, `--no-verify` 로 건너뛸 수 없다.

### 미확인

- 커밋 메시지도 push protection 검사 대상인지.
- 개인 계정 소유 공개 저장소에서 일반 패턴을 켤 수 있는지. 문서 문구로는 조직 저장소 전용이고, API 응답에 필드는 있지만 꺼져 있다. 켜 보지 않았다.

---

## 4. 직접 쓴 git pre-push 훅

### 사실

- `git push` 가 부른다. 인자 2개(원격 이름, 위치), 표준 입력으로 한 줄씩 `<로컬 ref> SP <로컬 해시> SP <원격 ref> SP <원격 해시> LF` 를 받는다. 원격 ref 가 없으면 원격 해시는 0으로만 된 값이다. [githooks]
- 0이 아닌 값으로 끝나면 `git push` 는 아무것도 보내지 않고 멈춘다. 이유는 표준 오류로 알린다. [githooks]
- `git push --no-verify` 는 pre-push 훅을 **완전히 건너뛴다**. [git-push]
- 훅 디렉터리는 기본 `$GIT_DIR/hooks`, `core.hooksPath` 로 바꿀 수 있다. 실행 비트가 없는 훅은 무시된다. [githooks]
- Windows 의 Git 은 실행할 파일 첫 줄의 `#!` 을 읽어 그 인터프리터(마지막 `/` 뒤 이름, 예: `sh`)로 실행한다. [mingw.c]
- 더미 판단 근거: 문서용 주소는 `192.0.2.0/24`, `198.51.100.0/24`, `203.0.113.0/24`(RFC 5737) [rfc5737]. 사설 주소는 `10/8`, `172.16/12`, `192.168/16`(RFC 1918) [rfc1918].
- 디스코드 웹훅 실행 경로는 `/webhooks/{webhook.id}/{webhook.token}`, 기본 URL 은 `https://discord.com/api` 다. [discord-wh] [discord-ref]
- **이 저장소의 현재 상태**(2026-11-09 확인):
  - `.githooks/pre-commit`(`#!/bin/sh`) 이 있고, 규칙 생성 파일 검사와 relay 단위 테스트를 돈다. pre-push 훅은 없다.
  - 이 클론의 로컬 설정 `core.hooksPath` 가 메인 체크아웃의 `<저장소>/.githooks` 절대 경로로 잡혀 있다. 훅 파일 주석은 켜는 방법으로 `git config core.hooksPath .githooks` 를 안내한다.
  - 추적 중인 파일에서 IPv4 꼴 문자열(`git grep -E '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'`)은 서로 다른 값 5개이고, 모두 RFC 5737 대역이다.

### 추론

- 훅은 사용자 규칙·허용 목록을 마음대로 짤 수 있다(IP 정규식에서 RFC 5737 대역 빼기, `<NAS 이름>` 같은 꺾쇠 자리 표시 빼기, 실제 PC 이름 목록과 대조 등). 대신 탐지 규칙·테스트·유지보수를 모두 직접 해야 한다.
- 커밋 메시지도 `git log` 로 꺼내 검사할 수 있다(위 두 도구와 다른 점).
- `core.hooksPath` 는 로컬 설정이라 버전 관리되지 않는다. 다른 PC·새 클론에서는 따로 켜야 한다.
- IPv4 정규식은 숫자 네 마디로 된 버전 문자열(`<주>.<부>.<수>.<빌드>`)에도 걸린다. 지금 추적 파일에는 그런 문자열이 없다(위 사실).

### 미확인

- 이 저장소의 워크트리들에서 `core.hooksPath` 훅이 실제로 도는지(설정 값만 확인했다).

---

## 5. 공통: 규칙 자체가 유출원이 되는 문제

### 사실

- gitleaks 는 설정을 `--config`, `GITLEAKS_CONFIG`(경로), `GITLEAKS_CONFIG_TOML`(내용)으로 저장소 밖에서 받을 수 있다. 저장소 안 `.gitleaks.toml` 은 4순위다. [gl-README]
- trufflehog 는 `--config` 로 설정 파일 경로를 받는다. [th-README]
- GitHub 사용자 지정 패턴은 GitHub 설정에 저장되지만 이 저장소에서는 쓸 수 없다(3절).

### 추론

- 실제 PC 이름·계정 이름·자기 공인 IP 를 잡으려면 그 실제 값을 규칙에 적어야 한다. 그 규칙 파일을 공개 저장소에 커밋하면 규칙이 곧 유출이다. 그래서 이런 규칙은 저장소 밖 파일(PC 로컬 설정 등)에 두어야 한다.
- 반대로 "모든 IPv4 를 잡고 RFC 5737 만 허용" 같은 모양 규칙은 실제 값이 없으므로 저장소에 둬도 된다.

---

## 범위 밖에서 보인 것

- `winget search gitleaks` 결과에 `Betterleaks.Betterleaks` 1.9.0(태그 `gitleaks`)이 함께 나왔다. 후보가 아니라서 조사하지 않았다.

## 미확인 모음

1. 네 후보 모두 실제 실행 확인 없음(설치 금지 범위). 특히 gitleaks 가 디스코드 웹훅 URL 을 정말 놓치는지.
2. trufflehog 디스코드 웹훅 토큰에 `_` 가 들어갈 수 있는지(디스코드 문서에 토큰 문자 집합이 없음).
3. trufflehog·GitHub push protection 이 커밋 메시지를 검사하는지.
4. pre-commit 프레임워크가 pre-push 단계에서도 `PRE_COMMIT=1` 을 넣는지(넣으면 trufflehog 훅 모드가 푸시 범위를 보지 않음).
5. 개인 계정 소유 공개 저장소에서 GitHub 일반 패턴을 켤 수 있는지.
6. Git Bash 에서 gitleaks·trufflehog `.exe` 실행 확인.
