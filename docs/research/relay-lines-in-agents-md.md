# AGENTS.md 에서 relay 줄을 뺄 때 영향받는 곳

- 이슈: hdmun/anything#131 (지도 #126)
- 조사일: 2026-11-21
- 기준: `origin/main` = `b9089cb`. relay 플러그인 3.1.x(역할 파일 스탬프 `relay-roles v3.1.0`)
- 빼기로 한 줄 (이미 정해진 일이다. 빼도 되는지는 다시 판단하지 않는다):
  - A. `agent-rules/project/10-agent-skills.md:7` (`AGENTS.md:9`) — 「구현 이슈를 쓸 때는 Skill 도구로 `relay:spec` 을 먼저 부른다. wayfinder 지도의 task 티켓 본문을 구현 이슈로 다시 쓸 때도 같다.」
  - B. `agent-rules/project/20-git.md:11` (`AGENTS.md:29`) — 「relay 일괄 진행의 진행자 세션은 예외다. …」
  - C. `agent-rules/project/30-relay.md:1-3` (`AGENTS.md:31-33`) — `## relay` 섹션 전체(역할 파일 링크, 「직접 고치지 않는다」, `.ai/relay-roles.json` → `/relay:init --force`)

**사실**은 파일·커밋·이슈에서 옮긴 것이다. **추론**은 그것을 줄 삭제에 적용한 판단이다. 줄을 실제로 빼서 돌려 보지는 않았다.

## 요약

| # | 곳 | 줄을 빼면 | 종류 |
| --- | --- | --- | --- |
| 1 | relay 진행자 세션(일괄 진행)이 이 저장소에서 돌 때 | B 가 없으면 진행자 세션이 `AGENTS.md:25`·`:28` 을 따라 푸시·force-with-lease 전에 사람에게 물을 수 있다. 사람이 없으니 멈춤 보고 없이 선다(#59 의 우려). 불변식만으로 되는지는 시험한 적이 없다(#70) | 동작 변경 |
| 2 | `plugins/relay/commands/init.md:56-57`, `plugins/relay/README.md:64` | C 가 없으면 `/relay:init` 이 역할 파일 링크를 `AGENTS.md` 에 다시 넣자고 제안한다. 「링크로만 도달한다」는 문구도 실제 dispatch 와 어긋난다. 워커는 dispatch 문구로 역할 파일을 받는다고 보지만, 워커를 띄워 확인하지는 않았다 | 문서 불일치 |
| 3 | `relay:spec` 발동 | A 가 없으면 `relay:spec` 은 description 으로만 불린다. 템플릿을 안 따른 이슈는 `handoff-check`·`batch-plan` 이 막으므로 다시 써야 한다 | 동작 변경 |
| 4 | 게이트·pre-commit | 원본을 고치고 `sh agent-rules/build.sh` 를 안 돌리면 게이트(`.ai/relay-roles.json:5-6`)와 `.githooks/pre-commit:14` 가 실패한다. 내용은 검사하지 않는다 | 절차 |
| 5 | 역할 파일(`.ai/roles/*`), `rules_doc` | 영향 없다. `rules_doc` 은 `AGENTS.md` 파일 자체를 가리키고, 그 설명(커밋 메시지, 브랜치, 이슈 트래커)은 줄을 빼도 맞다 | 없음 |
| 6 | `relay_cli.py` 의 `doctor`·`handoff-check`·`roles`, 테스트, `build.sh`, `docs/agents/` | 규칙 파일의 줄을 읽거나 검사하는 코드가 없다 | 없음 |

---

## 1. B 를 빼면: 일괄 진행 진행자 세션의 푸시·머지 허락

### 사실

- B 가 예외로 푸는 규칙은 그대로 남는다 — `AGENTS.md:25` 「푸시는 사용자가 요청할 때만 한다」, `AGENTS.md:28` 「force push, `reset --hard` 등 되돌리기 어려운 명령은 사전 확인 후 실행한다」.
- 같은 뜻이 relay 스킬 불변식에 이미 있다 — `plugins/relay/skills/relay/SKILL.md:60`: 「일괄 진행이면 사람의 시작 명령이 … 요청이다. 저장소 규칙의 「푸시는 요청할 때만」·「force push 는 사전 확인」은 이 셋에 대해 이미 허락된 것으로 본다.」
- 진행자 세션은 rebase 뒤 `publish push --force-with-lease` 를 쓴다 — `plugins/relay/skills/relay/references/merge.md:19`.
- B 와 SKILL.md:60 은 같은 커밋 `161914f`(I-79, 2026-11-12)에서 들어왔다. spec: `.ai/specs/I-79-batch-skill.md:190`(불변식), `:201-204`(20-git.md 줄).
- 두 곳에 둔 이유 — #59 결정 3절: 「relay 문서에만 적으면 이 저장소의 진행자 세션이 CLAUDE.md 를 따라 사람에게 확인을 묻는다. 사람이 없으니 멈춤 보고도 없이 그대로 선다.」 「다른 저장소에서 relay 불변식만으로 통하는지는 첫 실전에서 확인한다.」
- #70 은 이 물음을 시험하지 않기로 정했다 — 결정 댓글 「다른 저장소의 푸시 규칙과 relay 불변식의 충돌: 시험하지 않는다. 푸시 규칙이 있는 저장소는 `hdmun/anything` 뿐이고, 거기에는 `20-git.md` 에 예외 줄을 직접 넣는다. 비공개 저장소의 규칙 파일과 Orca 가 띄운 세션이 읽는 `~/.claude/CLAUDE.md` 에는 푸시 규칙이 없다.」
- `plugins/relay/docs/field-notes.md` 에도 불변식만으로 푸시·머지한 기록이 없다(일괄·batch·첫 실전·푸시로 찾음).

### 추론

- B 를 빼면 이 저장소는 「푸시 규칙은 있고 예외 줄은 없는」 유일한 경우가 된다. #59 가 피하려 한 경우이고, #70 이 시험하지 않기로 한 경우다. 불변식만으로 되는지는 확인된 적이 없다.
- 깨지는 코드는 없다. 바뀌는 것은 진행자 세션(모델)의 판단이다. 이 저장소에서 `/relay:batch` 를 돌리지 않으면 드러나지 않는다.
- 옮길 곳 후보:
  - 같은 뜻이 이미 `plugins/relay/skills/relay/SKILL.md:60` 에 있다. 따로 옮길 문장은 없다.
  - 이 저장소에서 일괄 진행을 계속 쓴다면, 불변식만으로 푸시·머지하는지 한 번 확인하는 일이 새로 생긴다.

## 2. C 를 빼면: `/relay:init` 과 README 의 「링크로만 도달한다」

### 사실

- `plugins/relay/commands/init.md:56-57` — 결과 보고 단계: 「저장소의 `AGENTS.md` 또는 `CLAUDE.md` 에 역할 파일 링크가 **없으면** 추가를 제안한다. 워커는 그 링크를 통해서만 역할 파일에 도달한다 — 링크가 없으면 파일이 있어도 읽히지 않는다.」
- `plugins/relay/README.md:64` — 「워커는 `AGENTS.md`/`CLAUDE.md`의 링크를 통해서만 역할 파일에 도달하므로 링크를 걸어 둔다.」
- 이 두 문구는 2026-09~10 에 들어왔다(`6949475` 2026-09-12, `9b6cdec` 2026-10-01).
- 그 뒤 `c4a4422`(2026-11-02, 워커를 `worker-start --agent` 로 띄운다)부터 진행자가 dispatch 의 `--spec` 에 역할 파일 경로를 직접 적는다:
  - 구현자 — `plugins/relay/skills/relay/references/implementer.md:36`: `I-<n> 구현. 역할: .ai/roles/implementer.md / spec: … / base: <base>`
  - 리뷰어 — `plugins/relay/skills/relay/references/reviewer.md:38`: `I-<n> 리뷰 rN. 역할: .ai/roles/reviewer.md / …`
- `relaylib/roles.py`(`/relay:init` 의 렌더링)는 규칙 파일의 링크를 확인하지 않는다. 링크 제안은 `init.md` 를 따르는 모델이 한다.
- C 는 `a60b0f7`(2026-11-11, 「AGENTS.md 에 relay 역할 파일 링크를 더한다」)에서 들어왔다.

### 추론

- C 를 빼도 워커는 dispatch 문구로 역할 파일을 연다. 끊기는 경로는 없다. 근거와 한계:
  - `orca orchestration worker-start --help`(1.4.267) — `--spec <text>` 는 그 문구로 새 Task 를 만든다. Orca 가이드 「If your prompt has a preamble with Task and Dispatch IDs, you are a worker: follow the preamble」(`orca skills get orchestration` 22행).
  - 역할 템플릿도 같은 전제다 — `plugins/relay/templates/implementer.md.tmpl:20` 「TASK 블록이 가리키는 `.ai/specs/…`」. spec 경로가 같은 `--spec` 문구에 있으므로 역할 경로도 워커에게 간다.
  - 워커를 띄워 preamble 을 직접 보지는 않았다.
- 바뀌는 것은 문서다:
  - `/relay:init` 을 이 저장소에서 다시 돌리면(`--force` 포함) 링크를 다시 넣자고 제안한다. 뺀 결정과 어긋난다.
  - `init.md:57`·`README.md:64` 의 「링크로만 도달한다」는 c4a4422 이후로 이미 사실과 다르다. C 를 빼면 그 어긋남이 이 저장소에서 드러난다.
- C 가 담은 나머지 내용의 다른 위치:
  - 「직접 고치지 않는다」 — 역할 파일 첫 줄 스탬프 `.ai/roles/implementer.md:1`·`.ai/roles/reviewer.md:1`, `plugins/relay/README.md:63`, `init.md:61-63`.
  - 「저장소 고유 값은 `.ai/relay-roles.json` 을 고친 뒤 `/relay:init --force`」 — `plugins/relay/README.md:60`·`:63`, `init.md:63`. 역할 파일 스탬프에는 「플러그인 템플릿을 고친 뒤」만 있고 `.ai/relay-roles.json` 은 없다.
  - 그래서 C 의 내용은 플러그인 문서에 다 있다. 옮길 것은 없다.

## 3. A 를 빼면: `relay:spec` 발동

### 사실

- A 는 `4a3c651`(I-73, 2026-11-11)에서 들어왔다. spec `.ai/specs/I-73-human-todo-section.md:17`, `:143-149`.
- A 를 둔 근거 — #60 결정 1절: 「이 저장소에서는 CLAUDE.md 지시문이 description 보다 확실하다(handoff SKILL.md 의 2026-11-03 eval)」, 「빠뜨려도 `handoff-check`·`batch-plan` 이 기계로 막는다」.
- wayfinder 문장을 붙인 근거 — #70 「`relay:spec` 호출 줄에 wayfinder 문장을 붙인다」: 「wayfinder 로 설계하던 세션은 description 만 보고 `relay:spec` 을 부르지 않을 수 있다. 부르지 않아도 `batch-plan` 이 시작 전에 막지만, 이슈를 다시 써야 한다.」
- `relay:spec` description(`plugins/relay/skills/spec/SKILL.md:3`)에 「wayfinder 지도의 task 티켓을 구현 이슈로 다시 쓸 때 부른다」가 이미 있다.
- 템플릿 위반은 `handoff-check` 의 `template:<태스크>` 검사가 FAIL 로 잡는다 — `plugins/relay/scripts/relaylib/handoff.py:179`.
- eval `plugins/relay/evals/spec-fires/` 는 description 발동을 본다. 채점 기준 `graders/criteria.md` 에 「The eval sandbox has no web access and no target repository」라고 적혀 있다. 이 저장소의 `AGENTS.md` 없이 도는 eval 이므로 A 를 빼도 결과가 바뀌지 않는다.

### 추론

- 깨지는 코드·테스트는 없다.
- 바뀌는 것: 이 저장소에서 구현 이슈를 쓰는 세션이 `relay:spec` 을 덜 부를 수 있다. 그러면 handoff 단계에서 FAIL 이 나고 이슈를 다시 쓴다. relay 를 강제하지 않기로 했으므로 의도한 변화다.
- 옮길 곳: 없다. description 이 같은 발동 조건을 이미 담고 있다.

## 4. 게이트·pre-commit·build.sh

### 사실

- `agent-rules/build.sh:44-52` 는 `project/*.md` 를 이름 순으로 이어 붙일 뿐이다. 특정 섹션·줄을 찾지 않는다. `30-relay.md` 를 지우면 그 섹션 없이 만들어진다.
- `agent-rules/README.md:23` — 「파일 하나는 `## 제목` 섹션 하나로 시작한다」. 빈 `30-relay.md` 를 남기면 이 규칙에 어긋나고 `AGENTS.md` 끝에 빈 줄만 남는다. 파일을 지우는 편이 맞다.
- `.githooks/pre-commit:7-17` — `agent-rules/`·`AGENTS.md` 가 스테이징되면 (1) 스테이징하지 않은 변경·추적하지 않는 파일이 없는지, (2) `build.sh --check` 가 통과하는지만 본다. 내용은 보지 않는다.
- `.ai/relay-roles.json:5-6` 의 게이트에 `sh agent-rules/build.sh --check` 가 들어 있다.

### 추론

- 원본 세 곳을 고친 뒤 `sh agent-rules/build.sh` 로 `AGENTS.md` 를 다시 만들고 함께 커밋하면 된다. `30-relay.md` 삭제는 `git rm` 으로 스테이징해야 pre-commit 의 (1) 을 통과한다.
- A 를 뺄 때 `10-agent-skills.md:6`·`:8` 의 빈 줄 하나도 함께 빼야 `### Issue tracker` 아래 빈 줄이 두 개가 되지 않는다.

## 5. 영향 없음을 확인한 곳

| 곳 | 확인한 것 |
| --- | --- |
| `.ai/relay-roles.json:3` `rules_doc` | 값은 `**[AGENTS.md](../../AGENTS.md)** — 이 저장소의 규칙(커밋 메시지, 브랜치, 이슈 트래커)`. 파일을 가리킬 뿐 섹션을 가리키지 않는다. 남는 `AGENTS.md` 에 세 가지가 다 있다 |
| `.ai/roles/implementer.md:22`, `.ai/roles/reviewer.md:21` | `rules_doc` 을 렌더링한 줄. 다시 만들 필요 없다 |
| `plugins/relay/scripts/relaylib/roles.py:23`, `:54` | `rules_doc` 이 비어 있지 않은지만 본다 |
| `plugins/relay/scripts/relay_cli.py:335-383` `doctor`, `relaylib/doctor.py` | 설정·버전·trust·gitleaks 만 본다. 규칙 파일을 읽지 않는다 |
| `relay_cli.py:385-394` `handoff-check`, `relaylib/handoff.py` | 이슈 본문(태스크 수·작성자·템플릿·「사람이 할 일」)만 본다 |
| `plugins/relay/tests/*.py` | `AGENTS.md` 를 읽는 테스트가 없다. `tests/helpers.py:17` 의 `rules_doc` 은 픽스처 문자열이다. `test_docs.py` 는 플러그인 스킬 문서만 읽는다 |
| `plugins/relay/templates/*.tmpl` | `{{RULES_DOC}}` 자리표시자만 있다 |
| `docs/agents/*.md` | relay·`relay:spec` 언급이 없다 |
| `.ai/specs/I-73-*.md`, `.ai/specs/I-79-*.md` | 줄을 넣으라고 한 옛 spec 스냅숏이다. 끝난 이슈의 기록이라 고치지 않는다 |

## 출처

- 저장소 파일: 위 각 항목의 `경로:줄`(기준 `b9089cb`)
- 커밋: `161914f`(B, SKILL.md:60), `4a3c651`(A), `a60b0f7`(C), `c4a4422`(dispatch 에 역할 경로), `6949475`·`9b6cdec`(「링크로만 도달」 문구)
- 이슈: #59 「relay 안에 넣나 따로 만드나」 결정 3절, #60 「구현 이슈를 relay 템플릿으로 쓰게 하기」 결정 1절, #70 「첫 실전 대상과 시험 방법」 본문과 결정 댓글, #126 지도 Notes
- Orca 1.4.267: `orca orchestration worker-start --help`, `orca skills get orchestration`(설치본, 읽기만)
