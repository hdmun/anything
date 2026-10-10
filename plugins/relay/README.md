# relay

[Orca](https://www.onorca.dev) orchestration 위에서 AI 코딩 에이전트 넷을 역할별로 묶어 태스크 하나를 **spec부터 머지 직전까지** 옮기는 Claude Code 플러그인.

| 역할 | 실행 주체 | 하는 일 |
|---|---|---|
| 설계자 | Claude Code · Opus | spec 작성, Run/Task 생성, SPEC_VIOLATION 중재 |
| 진행자 | Claude Code · Sonnet | 워커 기동, 대기, 게이트 재검증, 리뷰 분기, PR/브랜치 보고 |
| 구현자 | agy (Antigravity CLI) | spec을 코드로 옮기고 게이트를 통과시킨다 |
| 리뷰어 | codex | 커밋된 변경을 spec과 대조해 심각도별 JSON 리포트를 낸다 |

설계는 드물고 짧지만 판단이 무겁고, 진행은 잦고 길지만 대부분 조건 분기다. 그래서 둘을 다른 세션·다른 모델로 나눈다. 상태는 Orca(Run/Task/Dispatch)와 git이 소유하므로 진행 세션은 태스크마다 버린다.

## 준비물

1. **Orca** — `orca` CLI가 PATH에 있어야 한다. 진행 세션은 Orca 터미널 안에서 돈다.
2. **agy** — 워크트리를 `~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces`에 등록해야 한다(진행자가 기동 때 추가하고 성공 종료 때 지운다).
3. **codex** — `~/.codex/config.toml`에 아래 두 키가 필요하다. 없으면 Orca가 codex 기동을 감지하지 못하거나 업데이트 프롬프트에서 멈춘다.

   ```toml
   check_for_update_on_startup = false

   [tui]
   terminal_title = ["app-name", "activity", "project-name"]
   ```

4. **Python 3** — `/relay:init`이 역할 파일을 렌더링할 때 쓴다(표준 라이브러리만).

## 설치

마켓플레이스 소스는 이 저장소의 **로컬 폴더**다.

```bash
claude plugin marketplace add C:\Users\hdmun\scripts
claude plugin install relay@hdmun-scripts
```

설정 디렉터리를 여러 개 쓰면(`~/.claude`, `~/.claude-max`) 각각에서 설치한다.

## 사용

### 1. 저장소 준비 — `/relay:init`

relay를 쓸 저장소에서 한 번 실행한다. 워커가 읽는 역할 파일과 게이트 로그 `.gitignore` 항목을 만든다.

```
/relay:init            # 없으면 생성, 있고 다르면 거부
/relay:init --check    # 쓰지 않고 드리프트만 확인 (종료코드 1 = 드리프트)
/relay:init --force    # 템플릿으로 덮어쓰기
```

| 생성물 | 정본 |
|---|---|
| `.ai/roles/implementer.md`, `.ai/roles/reviewer.md` | 플러그인 `templates/` (공유 규범) + 저장소의 `.ai/relay-roles.json` (게이트 명령 등 고유분) |
| `.gitignore`의 `# >>> relay gate logs >>>` 블록 | `.ai/relay-roles.json`의 `gate_logs` |

역할 파일은 손으로 고치지 않는다. 공유 규범은 템플릿을, 저장소 고유분은 `.ai/relay-roles.json`을 고치고 `--force`로 다시 만든다.
워커는 `AGENTS.md`/`CLAUDE.md`의 링크를 통해서만 역할 파일에 도달하므로 링크를 걸어 둔다.

### 2. 설계 세션 (Opus)

"relay로 T-NNN 설계해줘"처럼 요청하면 `relay` 스킬이 발동한다.
`.ai/specs/T-NNN-<슬러그>.md`를 쓰고 `run-create`/`task-create`까지 한 뒤 **Run ID를 알려주고 끝난다.**

### 3. 진행 세션 (Sonnet)

새 세션에서 `/model sonnet`으로 바꾸고 "relay Run `<run_id>` 진행해줘"라고 요청한다. 태스크 하나를 끝까지 몰고 간다.

```
run-use → 워크트리·기준선 게이트 → agy 기동·전달 확인 → 대기
→ 게이트 재검증 → 구현 커밋 → 빈 diff 확인 → codex 리뷰
→ 심각도 분기 → 브랜치/PR 보고 → 워커 정리 → 세션 폐기
```

**머지는 하지 않는다.** 진행 세션은 브랜치와 커밋 목록(또는 PR)까지만 만들고, 머지는 사람이 한다.

#### 진행 세션이 멈추고 사람을 부르는 경우

| 상황 | 이유 |
|---|---|
| 같은 Task의 기동 실패 2회 | Orca는 3회째에 circuit-break한다. 원인을 해소한 뒤 새 Task로 재출발한다 |
| 워커가 프롬프트에 멈춤 / 출력 정지(구현 5분·리뷰 10분) | 자동 응답은 금지다 |
| 총 라운드 5회 초과 | 태스크를 중단한다 |
| `SPEC_VIOLATION`, 같은 지적 반복, 리뷰 라운드 3회 초과 | 사람 대신 **설계 세션(Opus)** 으로 넘긴다 — Orca decision gate로 남긴다 |

## 구조

```
plugins/relay/
  .claude-plugin/plugin.json      버전
  skills/relay/SKILL.md           설계·진행 세션 절차 (정본)
  skills/relay/references/        spec 템플릿, 리뷰 JSON 스키마
  commands/init.md                /relay:init
  scripts/relay_cli.py            단일 진입점 (relay_cli.py <sub>)
  scripts/relaylib/               relay 정책 — 정본은 이 코드와 tests/ (ADR 0001)
  scripts/render_roles.py         하위 호환 진입점 (= relay_cli.py roles)
  templates/*.md.tmpl             역할 파일 템플릿
  tests/                          단위 테스트 (unittest, 표준 라이브러리만)
  evals/                          판단형 평가 (claude plugin eval) — SKILL.md 산문이 옳은 행동을 끌어내는가
  CONTEXT.md                      용어집 (기동 실패, 라운드, 모델 계열 …)
  docs/adr/                       구조 결정 기록
  docs/plan.md                    진행 중인 작업 계획
```

## 플러그인 고치기

1. 이 폴더의 소스를 고친다. 설치본(`~/.claude*/plugins/cache/hdmun-scripts/relay/<version>/`)은 관리 복사본이라 직접 고치지 않는다.
   정책(분기·판정)을 바꾸면 `scripts/relaylib/` 과 `tests/` 를 함께 고친다. 테스트는 커밋 때 pre-commit hook이 돌린다(최초 1회 `git config core.hooksPath .githooks`). 직접 돌리려면:

   ```bash
   python -m unittest discover -s plugins/relay/tests
   ```

2. `SKILL.md`나 `templates/`를 바꿨으면 버전을 올리기 전에 평가를 돌린다. 케이스당 3회 × 플러그인 있음/없음 = 30회 실행이라 비용이 든다.

   ```bash
   cd plugins/relay
   claude plugin eval . --no-publish            # 기본 threshold 1.0 — 한 번이라도 어기면 종료코드 1
   ```

   실제 장애가 하나 생기면 `evals/`에 케이스를 하나 더한다. 테스트 3층의 분담: 정책 코드는 `tests/`, 산문(명령 대응·금지 행동·발동 조건)은 `evals/`, 실제 CLI 경계는 `relay_cli.py smoke`.

3. `.claude-plugin/plugin.json`의 `version`을 올린다.
4. 머지한 뒤 **main이 체크아웃된 상태에서** 설정 디렉터리마다 `claude plugin update relay`를 실행한다. 마켓플레이스 소스가 로컬 폴더라 체크아웃된 내용이 그대로 설치된다.
5. 진행 중인 relay 세션은 재시작해야 새 스킬을 읽는다.
6. 템플릿(`templates/`)이 바뀐 버전이면 relay를 쓰는 저장소마다 역할 파일을 갱신한다 — 아래 「사용 중인 저장소 갱신」.

## 사용 중인 저장소 갱신

플러그인을 업데이트해도 **저장소에 생성된 역할 파일은 그대로**다. 저장소마다 손으로 다시 렌더링해야 한다.

| 저장소 쪽 파일 | 플러그인에서 오는가 | 갱신 방법 |
|---|---|---|
| `.ai/roles/implementer.md`, `reviewer.md` | 예 (템플릿) | 아래 절차 |
| `.gitignore`의 relay 블록 | 예 (`gate_logs`) | 아래 절차가 함께 처리 |
| `.ai/relay-roles.json` | 아니오 — 저장소 소유 | 손으로 고친다 |
| `.ai/specs/`, `.ai/reviews/` | 아니오 — 산출물 | 건드리지 않는다 |

스킬(`SKILL.md`)만 바뀐 버전이면 저장소 쪽은 할 일이 없다. 바뀐 파일은 `git log -p <이전 태그나 커밋>.. -- plugins/relay/templates` 로 확인한다.

### 절차 (저장소 하나당 약 3분)

1. **진행 중인 태스크가 없는지 확인한다.** 워커는 **워크트리 안의** 역할 파일을 읽으므로, 태스크 도중에 main을 갱신해도 그 태스크엔 반영되지 않는다. 반대로 워크트리에서 갱신하면 변경이 태스크 diff에 섞여 리뷰에서 spec 밖 변경으로 잡힌다.

   ```bash
   git -C <repo> worktree list     # main 외에 relay 워크트리(T-NNN)가 있으면 그 태스크가 끝난 뒤에 한다
   ```

2. **기본 브랜치에서, 작업 트리가 깨끗한 상태로** 드리프트를 확인한다.

   ```bash
   P=$(ls -d ~/.claude/plugins/cache/hdmun-scripts/relay/*/ | sort -V | tail -1)   # 설치된 최신 버전
   cd <repo>
   python "$P/scripts/relay_cli.py" roles --plugin-root "$P" --repo . --check ; echo "exit=$?"
   ```

   Claude 세션 안이라면 `/relay:init --check` 와 같다.
   1.1.x 설치본에는 `relay_cli.py`가 없다 — 그때는 `python -X utf8 "$P/scripts/render_roles.py" …`(같은 인자)를 쓴다. `-X utf8`이 없으면 Windows 파이프 출력에서 cp949 `UnicodeEncodeError`로 죽는다.

3. **결과를 읽는다.**

   | 출력 | 뜻 | 할 일 |
   |---|---|---|
   | `OK 드리프트 없음` (exit 0) | 이미 최신 | 끝 |
   | `OK 내용 동일. 스탬프만 낡음` (exit 0) | 버전 스탬프만 다름 | 선택. 맞추려면 4번 |
   | `DRIFT ...` (exit 1) | 템플릿이 바뀌었다 | diff를 읽고, 템플릿 쪽이 맞으면 4번. 저장소 쪽이 맞으면 **템플릿을 고친다**(저장소 파일을 손으로 고치지 않는다) |
   | `치환되지 않은 자리표시자: [...]` (exit 2) | 새 버전이 변수를 추가했다 | 그 키를 `.ai/relay-roles.json`에 넣고 2번부터 다시 |
   | `필수 키가 없거나 비어 있습니다: ...` (exit 2) | 변수 파일이 불완전하다 | 그 키를 채우고 2번부터 다시 |

4. **덮어쓰고 커밋한다.**

   ```bash
   python "$P/scripts/relay_cli.py" roles --plugin-root "$P" --repo . --force
   git diff --stat                      # .ai/roles/*.md 와 .gitignore 만 바뀌어야 한다
   git add .ai/roles .gitignore
   git commit -m "chore(relay): 역할 파일 relay-roles v<버전> 반영"
   ```

5. **다음 태스크부터 적용된다.** 새 워크트리는 갱신된 main에서 분기하므로 따로 할 일이 없다.

### 현황 확인

relay를 쓰는 저장소와 각 역할 파일의 버전을 한 번에 본다.

```bash
for r in ~/repo/*/; do
  if [ -f "$r/.ai/relay-roles.json" ]; then
    echo "$(basename "$r")  $(head -1 "$r/.ai/roles/implementer.md" | grep -o 'v[0-9.]*')"
  fi
done
```

**모델 버전은 플러그인에 적지 않는다.** 기본값은 계열(Opus, Sonnet, agy 기본 모델)이고, 실제 버전은 커밋 트레일러(`Implemented-by:`, `Reviewed-by:`)로 남는다. 새 모델이 나와도 플러그인을 고칠 필요가 없다.

## 모델·effort 설정

역할별 model·effort 는 설정 파일로 정한다. 파일은 둘이고 필드 단위로 겹친다(저장소 파일이 사용자 파일을 덮는다). 둘 다 없으면 기본 동작이다.

| 파일 | 용도 |
|---|---|
| `~/.relay/models.json` | 사용자 전역 — 계정·쿼터에 따른 개인 선호 |
| `<저장소>/.ai/relay-models.json` | 저장소별 — 팀 통일, 또는 이 저장소만 다르게 |

```json
{
  "designer":    { "model": "opus",   "effort": "high" },
  "coordinator": { "model": "sonnet", "effort": "medium" },
  "implementer": { "model": "gemini-3.8-flash", "effort": "low" },
  "reviewer":    { "model": "gpt-6-luna", "effort": "high" }
}
```

| 역할 | 적용 방식 | 생략하면 |
|---|---|---|
| designer · coordinator | 강제하지 못한다. `relay_cli.py model <역할>` 이 `claude --model … --effort …` 를 알려 주고, 진행 세션이 현재 세션과 다르면 사용자에게 안내한다 | 사용자가 고른 세션 그대로 |
| implementer (agy) | `agy --model … --effort …` 로 기동 | agy 기본 모델 |
| reviewer (codex) | `codex --yolo -m … -c model_reasoning_effort=…` 로 기동 | `model` 은 **필수**(없으면 기동 거부), `effort` 는 `high` |

- **리뷰어 모델은 codex 의 `~/.codex/config.toml` 과 분리돼 있다.** `config.toml` 의 `model`(평소 용도)은 읽지 않고, 사전 조건 키(`check_for_update_on_startup`, `tui.terminal_title`)만 확인한다.
- 구현자 `model` 은 `agy models` 의 기본 이름(`gemini-3.8-flash`)이다. `gemini-3.8-flash-low` 처럼 effort 가 이름에 든 모델에 `effort` 를 같이 주면 agy 가 거부하므로 doctor 와 결정기가 미리 막는다.
- 모르는 역할·필드, 허용 문자(영문·숫자·`._:/-`) 밖의 model 값, 역할별 허용 목록 밖의 effort 는 거부한다. 값이 셸 명령줄에 들어가기 때문이다.
- 확인: `python scripts/relay_cli.py models` (4역할 한눈에) / `python scripts/relay_cli.py doctor` (`models` 줄).

### 설정 파일 만들기 — `models-init`

리뷰어·구현자의 model/effort 를 한 줄로 파일에 쓴다. 쓰기 전에 `agy models`, codex `models_cache.json` 과 대조해 안 되는 조합은 거부한다(종료코드 2, 아무것도 쓰지 않음).

```bash
cd <프로젝트>
python "$P/scripts/relay_cli.py" models-init \
  --reviewer-model gpt-6-luna --reviewer-effort high \
  --implementer-model gemini-3.8-flash --implementer-effort low
# wrote <프로젝트>/.ai/relay-models.json
# 저장소 설정이다 — 팀과 공유하려면 git add .ai/relay-models.json
```

(`P` 는 위 「1.3.0 으로 올리기」 4번의 설치 경로. 이 저장소 안에서는 `python plugins/relay/scripts/relay_cli.py …`.)

| 옵션 | 뜻 |
|---|---|
| `--repo <dir>` | 파일을 만들 프로젝트 (기본: 현재 디렉터리). 결과는 `<dir>/.ai/relay-models.json` |
| `--user` | 프로젝트 대신 사용자 전역 `~/.relay/models.json` 에 만든다 |
| `--print` | 쓰지 않고 내용만 출력한다 (미리 보기) |
| `--force` | 이미 있어도 덮어쓴다. 없으면 기존 파일이 있을 때 거부한다 |
| `--no-verify` | agy·codex 목록 대조를 건너뛴다 (오프라인) |
| `--output <file>` | 만들 파일 경로를 직접 지정 |

넘긴 값만 파일에 들어간다. 예를 들어 `--reviewer-effort xhigh` 만 주면 `{"reviewer": {"effort": "xhigh"}}` 가 되어 모델은 사용자 전역 파일 값을 그대로 쓴다. 설계자·진행자는 이 명령이 다루지 않는다(Claude 세션이라 파일로 강제할 수 없고, 필요하면 파일을 직접 편집한다).

### 리뷰어(codex) 모델 고르기

리뷰어 모델은 codex 를 평소에 쓰는 모델(`~/.codex/config.toml` 의 `model`)과 **별개**다. 설정 파일에 `reviewer.model` 이 없으면 리뷰 단계가 시작되지 않는다.

1. **목록과 effort 를 본다.** codex 가 캐시해 둔 모델 목록에서 `slug` 가 `model` 값이다.

   ```bash
   python -c "
   import json,pathlib
   for m in json.loads((pathlib.Path.home()/'.codex'/'models_cache.json').read_text(encoding='utf-8'))['models']:
       if m.get('visibility')=='list': print(m['slug'], [x['effort'] for x in m['supported_reasoning_levels']])"
   # gpt-6-luna [low, medium, high, xhigh, max]
   # gpt-6-sol  [low, medium, high, xhigh, max, ultra]
   ```

2. **`~/.relay/models.json` 에 적는다.** 모델마다 지원하는 effort 가 다르다(`ultra` 는 `gpt-6-sol` 계열만).

   ```json
   { "reviewer": { "model": "gpt-6-luna", "effort": "high" } }
   ```

   | 원하는 것 | `reviewer` |
   |---|---|
   | 기본 리뷰 | `{"model": "gpt-6-luna", "effort": "high"}` |
   | 어려운 변경만 깊게 | `{"model": "gpt-6-sol", "effort": "ultra"}` |
   | effort 만 바꾸기 | `{"model": "gpt-6-luna", "effort": "medium"}` (model 은 항상 필요) |

   `effort` 를 생략하면 `high` 다. `model` 을 생략하면 기동하지 않는다.
3. **저장소마다 다르게 하려면** `<저장소>/.ai/relay-models.json` 에 같은 형식으로 적는다. 필드 단위로 사용자 파일을 덮는다. 예를 들어 이 파일에 `{"reviewer": {"effort": "xhigh"}}` 만 있으면 모델은 사용자 파일의 것, effort 만 `xhigh` 다.
4. **확인한다.** `reviewer-model` 줄이 `OK` 여야 한다. 모델이 지원하지 않는 effort 는 `FAIL`, 목록에 없는 모델은 `WARN`(캐시가 낡았거나 사용자 정의 모델일 수 있어 막지 않는다).

   ```bash
   python scripts/relay_cli.py doctor | grep -E "codex|reviewer-model"
   # OK   codex           리뷰어 모델: gpt-6-luna / high (relay 설정 파일)
   # OK   reviewer-model  gpt-6-luna / high (codex 모델 목록에 있음)
   ```

5. **실제로 뜨는지 본다.** 설정대로 `codex --yolo -m … -c model_reasoning_effort=…` 로 기동한다.

   ```bash
   python scripts/relay_cli.py smoke --dir C:/Users/hdmun/scripts --agent codex
   ```

6. **`config.toml` 에서 필요한 것은 사전 조건 키 두 개뿐**이다(위 「준비물」 3번). `model` 은 있어도 없어도 리뷰어에 영향이 없다.

리뷰 리포트 커밋의 `Reviewed-by: codex/<모델>` 트레일러는 기동 명령에 준 `-m` 값, 즉 설정 파일의 `reviewer.model` 이다.

### 구현자(agy) 모델 고르기

1. **목록을 본다.** 왼쪽 ID 가 `model` 에 쓰는 값이다.

   ```bash
   agy models
   # gemini-3.8-flash-high    Gemini 3.8 Flash (High)
   # gemini-3.8-flash-low     Gemini 3.8 Flash (Low)
   # gemini-3.1-pro-high      Gemini 3.1 Pro (High)
   # claude-sonnet-5-5-medium Claude Sonnet 5.5 (Medium)
   ```

2. **ID 끝의 `-low`/`-medium`/`-high` 를 떼고** 기본 이름을 `model` 에, 그 레벨을 `effort` 에 적는다.

   | 원하는 것 | `models.json` 의 `implementer` |
   |---|---|
   | Gemini 3.8 Flash, 낮은 effort | `{"model": "gemini-3.8-flash", "effort": "low"}` |
   | Gemini 3.1 Pro, 높은 effort | `{"model": "gemini-3.1-pro", "effort": "high"}` |
   | Claude Sonnet 5.5, 중간 effort | `{"model": "claude-sonnet-5-5", "effort": "medium"}` |
   | 모델은 agy 기본, effort 만 | `{"effort": "high"}` |
   | 전부 agy 기본 | 이 키를 지운다 |

3. **모델마다 지원하는 effort 가 다르다.** `gemini-3.1-pro` 는 `low`/`high` 만 있다. 없는 조합은 agy 가 거부하며 기동 실패 예산을 쓰므로, 적은 뒤에 반드시 `doctor` 로 확인한다.

   ```bash
   python scripts/relay_cli.py doctor | grep models
   # OK   models  설정 1개 읽음; 구현자: gemini-3.8-flash / low
   ```

4. **하지 말 것**: `"model": "gemini-3.8-flash-low"` 처럼 레벨이 붙은 ID 에 `effort` 를 같이 주기. agy 가 `conflicts with --effort` 로 거부한다. 레벨 붙은 ID 만 쓰고 `effort` 를 비우는 것은 된다.
5. **실제로 뜨는지 확인한다.** Orca 에 등록된 워크트리가 필요하다(`plugins/relay` 같은 하위 폴더는 `selector_not_found`).

   ```bash
   python scripts/relay_cli.py smoke --dir C:/Users/hdmun/scripts --agent antigravity
   ```

   `"passed": true` 면 설정대로 기동되고 입력이 전달된 것이다. 같은 저장소의 설정을 바꾸지 않고 다른 값을 시험하려면 `--user-config <임시 파일>` 을 준다.

커밋 트레일러 `Implemented-by: agy/<모델>` 은 설정값이 아니라 agy 로그의 마지막 모델 라벨로 남는다. 설정이 실제로 적용됐는지 `git log` 에서 대조할 수 있다.

## 1.3.0 으로 올리기 (다른 작업 경로·설정 디렉터리)

1.3.0 은 `templates/` 를 바꾸지 않았다. **저장소의 역할 파일을 다시 렌더링할 필요가 없고**, 플러그인 설치본과 모델 설정 파일만 맞추면 된다.

1. **설정 디렉터리마다 플러그인을 갱신한다.** 마켓플레이스 소스가 로컬 폴더(`C:\Users\hdmun\scripts`)라 **main 이 체크아웃된 상태**여야 한다.

   ```bash
   git -C C:/Users/hdmun/scripts branch --show-current          # main 이어야 한다
   claude plugin marketplace update hdmun-scripts
   claude plugin update relay                                    # ~/.claude
   CLAUDE_CONFIG_DIR=~/.claude-max claude plugin update relay    # ~/.claude-max
   ```

2. **설치된 버전을 확인한다.** 둘 다 `1.3.0` 이어야 한다.

   ```bash
   for d in ~/.claude ~/.claude-max; do
     python -c "import json,sys; d=json.load(open(sys.argv[1]+'/plugins/installed_plugins.json')); print(sys.argv[1], [e['version'] for k,v in d['plugins'].items() if k.startswith('relay@') for e in v])" "$d"
   done
   ```

3. **모델 설정 파일을 만든다.** 사용자 전역은 한 번만, 저장소별은 통일이 필요한 저장소에서만 한다. **리뷰어 `model` 은 필수**다(없으면 리뷰 단계에서 멈춘다).

   ```bash
   mkdir -p ~/.relay
   cat > ~/.relay/models.json <<'JSON'
   { "reviewer":    { "model": "gpt-6-luna", "effort": "high" },
     "implementer": { "model": "gemini-3.8-flash", "effort": "low" } }
   JSON
   ```

   저장소별 덮어쓰기는 같은 형식으로 `<저장소>/.ai/relay-models.json` 에 적고 커밋한다.

4. **저장소마다 점검한다.** 저장소 루트에서 실행한다(약 10초). `FAIL` 이 없어야 한다.

   ```bash
   P=$(ls -d ~/.claude/plugins/cache/hdmun-scripts/relay/*/ | sort -V | tail -1)
   cd <repo>
   python "$P/scripts/relay_cli.py" doctor | grep -E "FAIL|plugin|models|codex"
   python "$P/scripts/relay_cli.py" models
   ```

5. **진행 중인 relay 세션은 재시작한다.** `/reload-plugins` 또는 세션 재시작. 안 하면 `FAIL plugin`(낡은 절차) 이 나온다.

## 알려진 한계

- 실전으로 아직 검증하지 못한 동작이 있다. 목록과 확인 계획은 [docs/plan.md](docs/plan.md)의 「미검증」에 있다.
- 실행은 순차다. DAG(`--deps`)는 처음부터 정의하되 병렬 전환은 연속 5개 태스크가 에스컬레이션 없이 통과한 뒤에 한다.
- Windows + Git Bash 기준으로 작성됐다. `/`로 시작하는 인자는 `MSYS_NO_PATHCONV=1`이 필요하다.

## 참고

- 용어: [CONTEXT.md](CONTEXT.md)
- 정책은 코드, orca 사용법은 Orca 가이드가 정본인 이유: [ADR 0001](docs/adr/0001-policy-in-code.md)
- Orca orchestration 정본 가이드: `orca skills get orchestration`
