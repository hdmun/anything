> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/75
> updatedAt: 2026-11-11T02:31:14Z

# 원격에 내보내기 전에 gitleaks 로 유출 검사를 한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

relay 진행자 세션은 사람이 보기 전에 이슈 브랜치를 푸시하고, PR 을 열고, 이슈에 멈춤 보고 코멘트를 단다. 공개 저장소에서는 그 순간 토큰·웹훅 URL·실제 IP·PC 이름이 공개된다. 결정([공개 저장소에 푸시하기 전 유출 검사](https://github.com/hdmun/anything/issues/55)): 진행자 세션이 원격에 내보내기 **직전**에 gitleaks 로 유출 검사를 한다. 모든 저장소(공개·비공개)와 모든 relay(일괄 진행, 일반 relay)에 적용한다. GitHub push protection 은 두 번째 방어선으로 이미 켜져 있다. git 훅은 쓰지 않는다(저장소마다 설치해야 하고, PR 본문·코멘트는 보지 못한다).

사실(2026-11-11, 이 PC, [준비 기록](https://github.com/hdmun/anything/issues/70#issuecomment-6784363464)):

- gitleaks 8.30.1 이 설치돼 있고 PATH 에 있다.
- `~/.relay/leak-rules.toml` 이 있다. 최상위 키는 `title` 과 `rules`(`[[rules]]` 3개, 키 `id`·`description`·`regex`·`keywords`) 뿐이다. 이 PC 의 실제 값은 이 파일에만 있다.
- `gitleaks stdin --config <파일> --redact` 는 걸리면 종료코드 1, 없으면 0 이다.
- `--report-format json --report-path -` 를 주면 결과 JSON 이 표준 출력으로 나온다. `--redact` 면 `Secret` 이 `REDACTED` 로 나온다.
- 사용자 규칙은 `[[rules]]` 의 `id`·`regex`·`keywords` 만으로 동작했다. 더미 IP(RFC 5737)는 걸리지 않았다.

이 태스크가 만드는 것:

1. 검사 후 내보내는 명령 `relay_cli.py publish push|pr|comment`(정본 `scripts/relaylib/leak.py`)
2. 플러그인 기본 규칙 `scripts/relaylib/leak_default.toml`
3. `doctor` 의 gitleaks·`~/.relay/leak-rules.toml` 검사(없으면 FAIL)
4. 진행자 문서(`finish.md`·`stop.md`)가 `git push`·`gh pr create`·`gh issue comment` 대신 이 명령을 쓰게 한다

`publish pr` 은 이미 열린 PR 이 있으면 새로 만들지 않고 그 PR 을 돌려준다. 재개 때 `gh pr create` 가 실패하던 문제다([한 이슈가 멈추면 나머지는](https://github.com/hdmun/anything/issues/58) 5절). 그 뒤의 머지 단계는 「relay 일괄 진행 구현」이 붙인다.

## 범위 밖 (건드리지 말 것)

- 머지(`gh pr merge`), 원격 브랜치 삭제, 일괄 진행 문서(`merge.md` 등): 「relay 일괄 진행 구현」.
- git 훅, 커밋 시점 검사: 하지 않기로 했다.
- 계정 이름 규칙: 만들지 않는다(Windows 계정 이름이 공개된 GitHub 아이디와 같아 규칙이 될 수 없다).
- local-markdown 트래커 경로(`finish.md` 경로 B): 푸시·PR·코멘트를 하지 않으므로 바뀌지 않는다.
- `skills/relay/references/verified-cli.json` 에 gitleaks 버전 넣기.
- `plugins/relay/README.md`, `.claude-plugin/plugin.json`.
- 이 저장소와 대상 저장소의 `.gitignore`.

## 변경 대상 파일

- `plugins/relay/scripts/relaylib/leak.py` — 신규
- `plugins/relay/scripts/relaylib/leak_default.toml` — 신규
- `plugins/relay/scripts/relay_cli.py` — 수정
- `plugins/relay/scripts/relaylib/doctor.py` — 수정
- `plugins/relay/tests/test_leak.py` — 신규
- `plugins/relay/tests/test_doctor.py` — 수정
- `plugins/relay/tests/test_docs.py` — 수정
- `plugins/relay/skills/relay/references/finish.md` — 수정
- `plugins/relay/skills/relay/references/stop.md` — 수정

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```
python relay_cli.py publish push    --worktree <dir> [--base origin/main] [--force-with-lease]
python relay_cli.py publish pr      --worktree <dir> --title <제목> --body-file <파일> [--base main]
python relay_cli.py publish comment --worktree <dir> --issue <이슈 URL> (--body-file <파일> | --leak-notice)
```

세 명령은 결정기다(ADR 0001): stdout 에 JSON 한 줄, 종료코드 0. 입력 오류는 종료코드 2, 사유는 stderr 한 줄.

| 명령 | `action` | 다른 필드 |
|---|---|---|
| push | `pushed` | `branch`, `range` |
| pr | `created` 또는 `exists` | `pr` (PR URL) |
| comment | `posted` | `url` (gh 가 출력한 코멘트 URL) |
| 셋 모두 | `stop` | `reason` 과 아래 필드 |

`stop` 의 `reason`:

- `leak`: `findings`(`[{"rule": id, "file": 경로, "line": 줄}]`, 값은 없다), `log`(워크트리 기준 로그 경로)
- `allowlist_changed`: `files`(범위 안에서 바뀐 허용 목록 파일)
- `push_failed`: `detail`(git stderr 의 마지막 비어 있지 않은 줄)
- `gh_failed`: `detail`(gh stderr 의 마지막 비어 있지 않은 줄)

```python
# plugins/relay/scripts/relaylib/leak.py
DEFAULT_CONFIG = pathlib.Path(__file__).with_name("leak_default.toml")
USER_RULES = pathlib.Path.home() / ".relay" / "leak-rules.toml"
REPO_ALLOW = ".ai/leak-allow.toml"
ALLOWLIST_FILES = (".gitleaksignore", REPO_ALLOW)
LOG_DIR = ".ai/leak"
LEAK_EXIT = 99
LEAK_NOTICE = "relay 멈춤 — 유출 검사에 걸려 내보내지 않았다. 자세한 결과는 이슈 워크트리 {worktree} 의 .ai/leak/ 로그에 있다."

class LeakError(Exception):
    """입력 오류(설정 파일 문법·키, gitleaks 없음·실행 실패). CLI 는 종료코드 2."""

def build_config(default_text, user_text, repo_allow_text):
    """세 TOML 텍스트 → gitleaks 설정 TOML 텍스트. user_text·repo_allow_text 는 None 일 수 있다."""

def scan_text(text, config_path, run):
    """글 하나 → [{"rule": id, "line": n}]. run(argv, stdin=...) -> (rc, stdout)."""

def scan_range(worktree, base, config_path, run, git):
    """base..HEAD 의 추가된 줄과 커밋 메시지 → [{"rule", "file", "line"}]. git(worktree, *args) -> stdout."""

def changed_allowlists(worktree, base, git):
    """base...HEAD 에서 바뀐 ALLOWLIST_FILES → [경로]."""

def write_log(worktree, op, findings):
    """findings 를 <worktree>/.ai/leak/<UTC 시각>-<op>.json 에 쓰고 워크트리 기준 경로를 돌려준다."""
```

`relay_cli.py` 의 `_run` 은 `_run(argv, timeout=120, cwd=None, stdin=None)` 으로 넓힌다. 기존 호출은 그대로 동작해야 한다.

## 동작 명세

### 정상 경로

**설정 만들기** (`build_config` + 임시 파일)

- `leak_default.toml`(플러그인 기본 설정):
  - `[extend] useDefault = true` — gitleaks 기본 규칙(토큰·키)을 쓴다.
  - 규칙 `relay-discord-webhook`: `discord(?:app)?\.com/api/webhooks/\d{17,20}/[\w-]+`
  - 규칙 `relay-ipv4`: 0~255 범위 옥텟 네 개를 점으로 이은 IPv4. 앞에 숫자·점·영문자가 붙어 있으면 걸리지 않는다. 뒤에 숫자·영문자가 붙어 있거나 「점 + 숫자」가 이어지면 걸리지 않는다. 문장 끝 마침표는 걸린다.
    - gitleaks 정규식은 Go RE2 라 lookbehind·lookahead 가 없다. 경계는 비캡처 그룹으로 쓰고 주소는 캡처 그룹 + `secretGroup` 으로 꺼낸다.
    - 규칙 허용 목록(대상 = secret): `192.0.2.0/24`·`198.51.100.0/24`·`203.0.113.0/24`(RFC 5737), `127.0.0.1`, `0.0.0.0`.
  - 규칙 `relay-windows-pc-name`: Windows 기본 PC 이름 `\bDESKTOP-[A-Z0-9]{7}\b`.
  - 규칙 id 에는 실제 값을 넣지 않는다(멈춤 보고에 id 가 적힌다).
- 사용자 파일(`USER_RULES`): 없으면 `LeakError`. 최상위 키는 `title`·`rules`·`allowlists` 만 허용한다. 그 밖의 키(예: `extend`)가 있으면 `LeakError`. `title` 은 버린다.
- 저장소 허용 목록(`<worktree>/.ai/leak-allow.toml`): 없어도 된다. 최상위 키는 `allowlists` 만 허용한다. 오탐을 사람이 main 에 커밋해 푸는 파일이다. 공개 저장소에는 더미 값만 둔다.
- 합친 설정 = 기본 설정 텍스트 + 사용자 파일의 `[[rules]]`·`[[allowlists]]` + 저장소 파일의 `[[allowlists]]`. 합친 텍스트를 `tomllib` 로 다시 읽어 깨졌으면 `LeakError`. 워크트리 **밖** 임시 파일에 써서 `--config` 로 넘기고, 명령이 끝나면 지운다.

**gitleaks 호출** — 늘 이 인자를 준다: `--config <합친 설정> --redact --ignore-gitleaks-allow --no-banner --exit-code 99 --report-format json --report-path -`.

- 종료코드 0 → 걸린 것 없음. 99 → 표준 출력 JSON 배열에서 `RuleID`·`File`·`StartLine` 을 읽는다. 그 밖 → `LeakError("gitleaks 실행 실패 (종료코드 N)")`. 실행 파일이 없으면(`_run` 이 127) → `LeakError("gitleaks 를 찾을 수 없다")`.
- 글: `gitleaks stdin …`, 글을 표준 입력으로 넘긴다.
- 범위의 추가된 줄: `gitleaks git <worktree> --log-opts "<base>..HEAD" …`.
- 범위의 커밋 메시지: `git log --format=%H <base>..HEAD` 의 커밋마다 `git log -1 --format=%B <sha>` 를 `gitleaks stdin` 에 넘긴다. 걸린 항목의 `file` 은 `커밋 메시지 <짧은 sha>` 다.

**`publish push`**

1. `changed_allowlists(worktree, base)` 가 비어 있지 않으면 `stop/allowlist_changed`. 푸시하지 않는다.
2. `scan_range` 에 걸린 것이 있으면 로그를 쓰고 `stop/leak`. 푸시하지 않는다.
3. `git -C <worktree> push -u origin HEAD` 를 실행한다. `--force-with-lease` 면 `git -C <worktree> push --force-with-lease origin HEAD` 다. 실패하면(push protection 거부 포함) `stop/push_failed`. 성공하면 `pushed`.

- `range` 는 `<base>..HEAD` 문자열이다. `base` 기본값은 `origin/main`. fetch 는 하지 않는다(`origin/main` 이 낡았으면 범위가 넓어질 뿐이다).

**`publish pr`**

1. 워크트리의 현재 브랜치로 열린 PR 을 찾는다(`gh pr list --head <브랜치> --state open --json url`, 워크트리를 현재 디렉터리로). 있으면 `exists` + 그 URL. 새로 만들지도, 본문을 고치지도 않는다.
2. 없으면 제목과 본문을 이어 `scan_text` 한다. 걸리면 로그를 쓰고 `stop/leak`.
3. `gh pr create --head <브랜치> --base <base> --title <제목> --body-file <파일>`. 성공하면 `created` + gh 가 출력한 PR URL. 실패하면 `stop/gh_failed`.

**`publish comment`**

1. 본문: `--body-file` 의 내용이다. `--leak-notice` 면 `LEAK_NOTICE` 의 `{worktree}` 에 워크트리 디렉터리 **이름**(전체 경로가 아님)을 채운 글이다.
2. `scan_text`. 걸리면 로그를 쓰고 `stop/leak`. 코멘트를 달지 않는다.
3. `gh issue comment <이슈 URL> --body-file <파일>`. 성공하면 `posted` + gh 가 출력한 코멘트 URL. 실패하면 `stop/gh_failed`.

**로그** — `write_log` 는 `<worktree>/.ai/leak/` 를 만들고, 그 안에 `*` 한 줄짜리 `.gitignore` 를 둔다. 그러면 저장소 `.gitignore` 를 고치지 않고도 디렉터리째 git 이 무시한다. 로그에는 `--redact` 된 gitleaks 결과와 `findings` 만 넣는다. 실제 값은 들어가지 않는다.

**doctor** — 검사 둘을 더한다.

- `gitleaks`: `gitleaks version` 이 되면 `ok`(detail 은 버전). 안 되면 `fail` 「gitleaks 를 찾을 수 없다 (PATH) — 유출 검사를 할 수 없다」, fix 「gitleaks 를 설치한다 (Windows: winget `Gitleaks.Gitleaks`)」.
- `leak-rules`: `~/.relay/leak-rules.toml` 이 있고 TOML 로 읽히며 허용된 최상위 키만 있으면 `ok`(detail 은 규칙 개수, 빈 파일도 `ok`). 없으면 `fail` 「~/.relay/leak-rules.toml 이 없다 — 이 PC 의 실제 값 목록 없이 유출 검사를 할 수 없다」, fix 「빈 파일이라도 만든다. 이 PC 의 실제 IP·PC 이름을 [[rules]] 로 적는다」. 문법·키 오류면 `fail` 과 오류 문구.
- 사실 수집은 지금처럼 `relay_cli.cmd_doctor` 가 하고, 판정은 `doctor.evaluate` 가 한다. facts 에 해당 키가 없으면 그 검사를 더하지 않는다(기존 테스트가 facts 를 일부만 준다. `plugin_version`·`orca_skills` 와 같은 방식).

**진행자 문서**

- `finish.md` 경로 A
  - `git -C <worktree> push -u origin HEAD` 와 `gh pr create …` 블록을 `python "$RELAY/scripts/relay_cli.py" publish push --worktree <worktree>` → `python "$RELAY/scripts/relay_cli.py" publish pr --worktree <worktree> --title "<부모 이슈 제목>" --body-file <본문 파일>` 로 바꾼다.
  - 결과 처리: `stop` 이면 멈춤 보고 — (h). `exists` 면 PR 을 새로 만들지 않았다는 것을 보고에 적는다(재개 때 생긴다).
  - 「진행자는 `git push`·`gh pr create`·`gh issue comment` 를 직접 부르지 않는다. 그 앞에 유출 검사가 있다(`publish`).」 한 줄을 둔다.
- `stop.md` 멈춤 보고
  - 3의 코멘트는 `python "$RELAY/scripts/relay_cli.py" publish comment --worktree <worktree> --issue <이슈 URL> --body-file <파일>` 로 단다.
  - 그 명령이 `stop/leak` 이면 `publish comment … --leak-notice` 로 고정 문장만 단다. 그것도 실패하면 세션 출력에만 남긴다.
  - 유출 검사로 멈춘 경우(푸시·PR 의 `stop/leak`·`allowlist_changed`)의 보고: 첫 줄에 `파일:줄`·규칙 id 만 적고 값은 적지 않는다. 로그 경로(`.ai/leak/…`)를 적는다. 재개 줄에는 두 길을 적는다.
    - 오탐: `~/.relay/leak-rules.toml` 이나 저장소의 `.ai/leak-allow.toml`(사람이 main 에 커밋)을 고친 뒤 같은 이슈로 `relay:handoff`.
    - 진짜 값: 원인(예: 이슈 본문의 실제 값)을 고치고, 이슈 워크트리와 브랜치를 지운 뒤 같은 이슈로 `relay:handoff`.
    - 진행자는 커밋 이력을 고치지 않는다.
  - 트리거 표에 「`publish` 의 `stop`」 행을 더한다: 멈춤 보고, 브랜치·워크트리는 남긴다.
- `test_docs.py`: relay 스킬 문서에 `push -u origin`·`gh pr create`·`gh issue comment` 가 없고 `relay_cli.py" publish` 가 있다고 단언한다.

### 엣지 케이스

규칙(`leak_default.toml`)이 다루는 입력을 아래로 한정한다. **열거하지 않은 경우는 범위 밖이다.**

| # | 입력 | 결과 |
|---|---|---|
| 1 | RFC 5737 주소(예: `192.0.2.10`, `198.51.100.7`, `203.0.113.200`) | 안 걸림 |
| 2 | `127.0.0.1`, `0.0.0.0` | 안 걸림 |
| 3 | 사설 IP(10/8, 172.16/12, 192.168/16 범위의 주소) | `relay-ipv4` |
| 4 | 공인 IP(RFC 5737 밖) | `relay-ipv4` |
| 5 | 문장 끝 마침표가 붙은 사설 IP | `relay-ipv4` |
| 6 | 옥텟 하나가 255 를 넘는 네 마디(예: `300.1.1.1`) | 안 걸림 |
| 7 | 세 마디 버전(`1.2.3`) | 안 걸림 |
| 8 | 다섯 마디 버전(`1.2.3.4.5`) | 안 걸림 |
| 9 | 옥텟 범위 안의 네 마디 버전 문자열 | `relay-ipv4` (오탐. 저장소 허용 목록으로 푼다) |
| 10 | 디스코드 웹훅 URL(17~20자리 숫자 id + 토큰), `discord.com`·`discordapp.com` 둘 다 | `relay-discord-webhook` |
| 11 | 테스트 더미 `discord.com/api/webhooks/1/token` | 안 걸림 |
| 12 | `DESKTOP-` + 영문 대문자·숫자 7자 | `relay-windows-pc-name` |
| 13 | `DESKTOP-` + 6자 또는 8자 | 안 걸림 |

**테스트 픽스처 주의**: 3·4·5·9·10·12 의 걸리는 값을 테스트 소스에 글자 그대로 쓰지 않는다. 이 저장소의 브랜치 푸시도 이 검사를 거치므로, 그대로 쓰면 relay 가 자기 테스트 파일에서 멈춘다. 실행 중에 조각을 이어 만든다(예: `".".join(["10", "1", "2", "3"])`).

명령의 경우:

- `publish push`: 범위에서 `.gitleaksignore` 나 `.ai/leak-allow.toml` 이 바뀜 → `allowlist_changed`(gitleaks 를 부르지 않는다). 커밋 메시지에만 걸림 → `leak`, `file` 은 `커밋 메시지 <짧은 sha>`. 범위에 커밋이 없음 → 검사할 것이 없으므로 그대로 푸시한다.
- `publish pr`: 열린 PR 있음 → `exists`, `gh pr create` 를 부르지 않는다(가짜 `run` 의 호출 기록으로 테스트). 본문에 걸림 → `stop/leak`, `gh pr create` 를 부르지 않는다.
- `publish comment`: `--body-file` 과 `--leak-notice` 를 함께 주거나 둘 다 주지 않음 → 입력 오류(종료코드 2). 본문에 걸림 → `stop/leak`, `gh issue comment` 를 부르지 않는다.
- 사용자 파일 없음, 사용자 파일에 `[extend]` → 입력 오류(종료코드 2).
- 저장소 허용 목록이 RFC 5737 밖 주소 하나를 허용 → 그 주소는 안 걸리고 다른 주소는 걸린다.

### 에러 처리

- `leak.LeakError` 를 `relay_cli.main()` 의 입력 오류 except 에 더한다(종료코드 2).
- `stop` 은 오류가 아니다: 종료코드 0, JSON 의 `action` 으로 알린다.

## 기존 코드 참조

- `plugins/relay/scripts/relay_cli.py:279` — `_run`: 실행 파일이 없으면 `(127, "")`. Windows 에서는 `shell=True`.
- `plugins/relay/scripts/relay_cli.py:323` — `cmd_doctor`: 사실을 모아 `doctor.evaluate` 에 넘긴다.
- `plugins/relay/scripts/relay_cli.py:541` — `main()` 의 입력 오류 except.
- `plugins/relay/scripts/relaylib/doctor.py:114` — `_orca_skill`: 검사 하나의 모양(`_check(name, status, detail, fix)`).
- `plugins/relay/scripts/relaylib/handoff.py:71` — `check(issue_ref, run)`: `run` 을 주입받아 테스트에서 가짜 트래커로 바꾸는 방식. `leak.py` 도 `run`·`git` 을 주입받는다.
- `plugins/relay/tests/test_handoff.py` — `tracker()`: 가짜 `run` 이 호출을 기록하는 방식.

## 인수 조건

- [ ] 엣지 케이스 표 1~13 을 실제 gitleaks 로 확인하는 테스트가 있다. gitleaks 가 PATH 에 없으면 그 테스트만 건너뛴다(`unittest.skipUnless`). 이 PC 에는 있으므로 게이트에서 돈다. 사용자 파일 자리에는 임시 빈 규칙 파일을 쓴다.
- [ ] `publish push`·`pr`·`comment` 의 `action` 마다, `stop` 의 `reason` 마다 가짜 `run`·`git` 테스트가 있다.
- [ ] `publish pr` 이 열린 PR 이 있을 때 `gh pr create` 를 부르지 않고 `exists` 를 낸다(테스트).
- [ ] `doctor.evaluate` 가 gitleaks 가 없거나 `~/.relay/leak-rules.toml` 이 없을 때 `fail` 검사를 낸다(facts dict 테스트).
- [ ] relay 스킬 문서에 `push -u origin`·`gh pr create`·`gh issue comment` 가 없다(`test_docs`).
- [ ] 게이트 명령: `python -m unittest discover -s plugins/relay/tests -q && sh agent-rules/build.sh --check` — 저장소 루트에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 걸린 값(`Secret`·`Match`)을 출력·로그·JSON 에 넣는 것, `--redact` 를 빼는 것.
- `--ignore-gitleaks-allow` 를 빼는 것, 규칙을 약하게 바꿔 테스트를 통과시키는 것.
- 테스트에서 실제 `~/.relay/leak-rules.toml` 을 읽거나 고치는 것(임시 파일을 쓴다).
- 실제 원격에 푸시하거나 실제 PR·코멘트를 만드는 테스트.
- 이 저장소의 `.gitignore` 를 고치는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
