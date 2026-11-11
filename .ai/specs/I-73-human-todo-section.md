> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/73
> updatedAt: 2026-11-11T09:54:39Z

# 구현 이슈에 「사람이 할 일」 필수 절을 두고 relay:spec 스킬로 쓰게 한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

relay 는 Orca 위에서 구현 이슈 하나를 PR 까지 옮기는 Claude Code 플러그인이다(`plugins/relay/`). 설계 세션이 구현 이슈를 쓰고 `relay:handoff` 로 진행자 세션을 띄운다. handoff 와 진행자 세션은 `relay_cli.py handoff-check`(기동 전 검사, 정본 `scripts/relaylib/handoff.py`)로 이슈가 템플릿을 따르는지 기계로 본다.

이 태스크에서 바꾸는 것은 셋이다.

1. **「사람이 할 일」 필수 절.** 구현 이슈마다 사람만 할 수 있는 일(관리자 권한, 실제 기기 시험 등)을 `머지 전:`·`머지 뒤:` 두 줄로 적는다. 앞으로 만들 일괄 진행은 `머지 전:` 에 할 일이 있으면 시작하지 않고, 진행자 세션은 이 절을 PR 본문에 옮긴다(둘 다 다른 이슈의 일). 이 태스크는 절의 판정을 `handoff-check` 에 넣는다. 일반 relay 에서도 필수다.
2. **새 스킬 `relay:spec`.** 지금 구현 이슈를 쓰는 규칙은 `relay:handoff` 1절과 `skills/handoff/references/spec-template.md` 에 있다. handoff 는 "다 쓴 이슈를 넘길 때" 발동하므로 쓰는 동안에는 불리지 않는다. 쓰는 규칙과 템플릿을 모델이 부를 수 있는 새 스킬 `relay:spec` 으로 옮긴다.
3. **이 저장소 규칙 한 줄.** `agent-rules/project/10-agent-skills.md` 에 `relay:spec` 호출 줄을 넣고 `AGENTS.md` 를 다시 만든다(`agent-rules/` 가 원본이고 `AGENTS.md` 는 생성 파일이다. 이 저장소에는 `CLAUDE.md` 가 없고 Claude Code 도 `AGENTS.md` 를 읽는다).

결정 출처: [구현 이슈를 relay 템플릿으로 쓰게 하기](https://github.com/hdmun/anything/issues/60) 1~4절, [첫 실전 대상과 시험 방법](https://github.com/hdmun/anything/issues/70) 「`relay:spec` 호출 줄에 wayfinder 문장을 붙인다」, [일괄 진행 한 번의 상한](https://github.com/hdmun/anything/issues/69) 「반복 지적은 감지하지 않고 미리 막는다」.

## 범위 밖 (건드리지 말 것)

- `skills/relay/` 아래 진행자 문서(`finish.md` 의 PR 본문 사본 등): 「relay 일괄 진행 구현」에서 한다.
- 일괄 진행용 쓰는 규칙(blocking 으로 잇기, `/relay:batch`): 「relay 일괄 진행 구현」이 `relay:spec` 에 더한다.
- `plugins/relay/README.md`, `.claude-plugin/plugin.json` 버전: 「relay 일괄 진행 구현」에서 한 번에 고친다.
- `plugins/relay/CONTEXT.md`, `plugins/relay/docs/adr/`: 이미 반영됐다.
- `snapshot`·`resume` 등 다른 `relay_cli` 명령.
- eval 케이스(`plugins/relay/evals/`) 수정과 실행.

## 변경 대상 파일

- `plugins/relay/skills/spec/SKILL.md` — 신규
- `plugins/relay/skills/spec/references/spec-template.md` — 신규 (`skills/handoff/references/spec-template.md` 를 `git mv` 로 옮긴 뒤 수정)
- `plugins/relay/skills/handoff/references/spec-template.md` — 삭제 (위로 옮김)
- `plugins/relay/skills/handoff/SKILL.md` — 수정
- `plugins/relay/scripts/relaylib/handoff.py` — 수정
- `plugins/relay/tests/test_handoff.py` — 수정
- `plugins/relay/tests/test_docs.py` — 수정
- `agent-rules/project/10-agent-skills.md` — 수정
- `AGENTS.md` — 수정 (`sh agent-rules/build.sh` 가 다시 만든 결과만)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```python
# plugins/relay/scripts/relaylib/handoff.py
HUMAN_HEADING = "## 사람이 할 일"

def human_todo(body):
    """「사람이 할 일」 절 → (todo, problems).
    todo = {"before": [항목 글], "after": [항목 글]} — 값이 정확히 `없음` 이면 빈 목록.
    problems = [문제 문자열]. 문제가 하나라도 있으면 todo 는 None. 절이 없으면 (None, ["「사람이 할 일」 절이 없다"])."""

def check(issue_ref, run):
    """구현 이슈 → {"checks": [...], "tasks": [{task, url, title}],
                    "human": {"url": <절을 읽은 이슈 URL>, "before": [...], "after": [...]} 또는 None}.
    입력 오류(참조·읽기 실패)는 IssueError."""
```

`check` 의 기존 반환 키(`checks`·`tasks`)와 기존 검사(`tasks`·`template:*`·`author:*`)는 바꾸지 않는다. `human` 키와 아래 검사만 더한다.

## 동작 명세

### 정상 경로

**`human_todo(body)`**

`body` 에서 제목 줄이 `## 사람이 할 일` 인 절을 읽는다. 범위와 HTML 주석 제거는 기존 `_section` 과 같다(다음 `## ` 줄 전까지).

- 절 안에서 `머지 전:` 줄과 `머지 뒤:` 줄을 찾는다. 줄 모양: 앞 공백, 선택적 불릿(`- ` 또는 `* `), `머지 전` 또는 `머지 뒤`, 선택적 공백, `:`, 값. 정규식 예: `^(\s*)(?:[-*]\s+)?머지 (전|뒤)\s*:\s*(.*)$`.
- 줄의 **값**(같은 줄 `:` 뒤 글, 앞뒤 공백 제거)과 **하위 항목**으로 그 줄의 할 일 목록을 만든다.
  - 하위 항목: 그 줄 바로 아래로 이어지는 줄 중 들여쓰기가 그 줄보다 깊은 줄들이다. 빈 줄은 건너뛰고, 들여쓰기가 그 줄 이하인 비어 있지 않은 줄에서 끝난다. 그 가운데 **가장 얕은 들여쓰기**에 있는 불릿 줄(`- ` 또는 `* `) 하나가 항목 하나다. 더 깊은 줄(번호 목록, 더 깊은 불릿, 이어지는 문장)은 바로 앞 항목에 속하고 따로 세지 않는다.
  - 항목 글은 불릿 뒤 글에서 체크박스(`[ ]`, `[x]`, `[X]`)와 앞뒤 공백을 뗀 것이다.
- 값이 정확히 `없음` 이고 하위 항목이 없으면 → `[]`.
- 값이 비어 있지 않고 `없음` 이 아니면 → `[값] + 하위 항목들`.
- 값이 비어 있으면 → `하위 항목들` (1개 이상이어야 한다).
- 절 안의 다른 글(설명 문장 등)은 무시한다.

예: 절 본문이 아래와 같으면 `before = []`, `after = ["NAS 에 설치", "실제 접속으로 알림을 본다"]` 다.

```
구현자·리뷰어는 이 절의 일을 하지 않는다.

- 머지 전: 없음
- 머지 뒤:
  - [ ] NAS 에 설치
  - [ ] 실제 접속으로 알림을 본다
    1. 알림이 온다
    2. 시각이 맞다
```

**`check(issue_ref, run)`** — 기존 검사 뒤에 「사람이 할 일」 검사를 더한다.

- 하위 이슈가 없으면 이슈 자체 본문에 `human_todo` 를 적용한다. 검사 이름은 `human:<태스크 ID>`(예: `human:I-12`).
- 하위 이슈가 있으면 **부모** 본문에 적용한다(검사 이름 `human:<부모 ID>`). 그리고 하위 이슈마다 본문에 「사람이 할 일」 절(`_section(body, HUMAN_HEADING)` 이 `None` 이 아님)이 있으면 `human-misplaced:<하위 ID>` 를 `fail` 로 더한다. detail 「하위 이슈에 「사람이 할 일」 절이 있다」, fix 「「사람이 할 일」 절을 부모 이슈로 옮긴다」. 근거: 검사기는 부모만 읽으므로 하위 이슈에 적은 `머지 전:` 할 일은 조용히 무시된다.
- `human:*` 검사: 문제가 없으면 `ok`, detail 은 `머지 전 <N>개 · 머지 뒤 <M>개`(0개면 `없음`, 예: `머지 전 없음 · 머지 뒤 2개`). 문제가 있으면 `fail`, detail 은 문제를 `; ` 로 이은 것, fix 「relay:spec 의 references/spec-template.md 의 「사람이 할 일」 절 형식으로 고친다」.
- 반환값 `human`: 문제가 없으면 `{"url": <절을 읽은 이슈의 url>, "before": [...], "after": [...]}`, 있으면 `None`.
- local-markdown 이슈(`.scratch/…`)도 같은 규칙이다(하위 이슈가 없으므로 이슈 자체).
- 기존 `template:*` 검사의 fix 문구 「relay:handoff 의 references/spec-template.md 형식으로 이슈 본문을 고친다」를 「relay:spec 의 references/spec-template.md 형식으로 이슈 본문을 고친다」로 바꾼다.
- 모듈 docstring 의 「검사 셋」 줄에 「사람이 할 일」 절을 더한다.

**`relay:spec` 스킬** (`skills/spec/SKILL.md`)

- 머리말: `name: spec`. `description` 은 작은따옴표로 감싼 한 줄이다(따옴표 없는 `: ` 가 YAML 을 깨뜨린 회귀가 있었다, `test_docs.py` `Frontmatter`). 구현 이슈(relay spec)를 **쓰거나 고칠 때** 쓴다고 적고, 발동 예시(「구현 이슈 써줘」, 「relay 템플릿으로 이슈 작성」, wayfinder 지도의 task 티켓을 구현 이슈로 다시 쓸 때)를 넣는다. 다 쓴 이슈를 진행자에게 넘기는 일은 `relay:handoff` 라고 적는다. `disable-model-invocation` 은 넣지 않는다(모델이 부를 수 있어야 한다).
- 본문 순서:
  1. 이 스킬이 하는 일 한 단락: 구현 이슈 본문을 `references/spec-template.md` 형식으로 쓰고, 마지막에 기동 전 검사를 돌린다. 진행자 세션은 띄우지 않는다.
  2. `$RELAY` 정의 줄: 이 스킬을 불러왔을 때 표시되는 *Base directory* 에서 두 단계 위(플러그인 루트)다.
  3. 「쓰는 규칙」: 지금 `skills/handoff/SKILL.md` 「## 1. 구현 이슈를 쓴다」의 본문(정본은 구현 이슈, 템플릿을 먼저 Read, 하위 이슈 = 태스크·5개 이하, 부모 이슈의 내용, 작성자 권한, 위임 가치가 음수인 태스크, 대상 코드를 먼저 읽기)을 **옮긴다**. 그리고 아래 셋을 더한다.
     - 「사람이 할 일」 절은 하위 이슈가 없으면 이슈 자체에, 있으면 **부모에만** 둔다. 하위 이슈에 두면 기동 전 검사가 실패한다.
     - `머지 전:` 은 머지가 곧 배포인 저장소에서만 생긴다. 시작 전에 할 수 있는 일(도구 설치 등)은 이 절에 적지 않고 handoff 전에 끝낸다. 게이트가 그 일을 전제하면 「배경」에 사실로 적는다(예: "Pester 5 가 설치돼 있다").
     - 검사기·파서처럼 입력 경우가 열린 태스크는 다룰 경우를 spec 에 열거하고, 열거하지 않은 경우는 범위 밖이라고 적는다. 근거: 리뷰어가 라운드마다 놓친 경우를 새로 찾아 라운드가 길어진 사례가 있었다.
  4. 「끝내기」: `python "$RELAY/scripts/relay_cli.py" handoff-check --issue <이슈 URL>` 을 돌린다. 읽기만 하는 검사다. `FAIL` 이면 `→` 줄대로 이슈를 고치고 다시 돌린다. 통과하면 끝난다. 진행자 세션을 띄우는 것은 `relay:handoff` 다.
- orca 명령은 적지 않는다.

**템플릿** (`skills/spec/references/spec-template.md`)

- 맨 위 주석에 한 문장을 더한다: 「사람이 할 일」 절은 부모 이슈(하위 이슈가 없으면 이슈 자체)에만 둔다. 하위 이슈에서는 이 절을 지운다.
- 「인수 조건」 절(그 안의 설계자 주의 주석 포함) 바로 뒤, 「하지 말아야 할 것」 앞에 제목 줄 `## 사람이 할 일` 과 아래 본문을 넣는다.

  ```
  구현자·리뷰어는 이 절의 일을 하지 않는다. 인수 조건은 이 일 없이 판정할 수 있어야 한다.

  - 머지 전: 없음
  - 머지 뒤:
    - [ ] <사람만 할 수 있는 일. 없으면 이 줄을 지우고 `- 머지 뒤: 없음` 으로 쓴다>

  <!-- 설계자 주의 (이 주석은 실제 spec에서 지운다): `머지 전:` 은 머지가 곧 배포인 저장소에서만 생긴다. 시작 전에 할 수 있는 일은 여기 적지 않고 handoff 전에 끝낸다. -->
  ```

  템플릿을 그대로 두면 `<…>` 자리표시 때문에 `human:*` 이 `FAIL` 이다(의도된 동작).
- 그 밖의 템플릿 내용은 바꾸지 않는다.

**`relay:handoff`** (`skills/handoff/SKILL.md`)

- 「## 1. 구현 이슈를 쓴다」의 본문을 이 한 줄로 줄인다: "이슈가 없거나 템플릿을 따르지 않으면 `relay:spec` 으로 쓴다." 제목은 그대로 둔다.
- 2절의 `handoff-check` 설명에 검사 대상을 더한다: 「태스크마다 템플릿 필수 절(변경 대상 파일, 인수 조건의 `게이트 명령:`), 구현 이슈의 「사람이 할 일」 절, 작성자 권한」.

**이 저장소 규칙**

`agent-rules/project/10-agent-skills.md` 의 `### Issue tracker` 단락 바로 아래에 빈 줄 하나와 이 줄을 넣는다.

```
구현 이슈를 쓸 때는 Skill 도구로 `relay:spec` 을 먼저 부른다. wayfinder 지도의 task 티켓 본문을 구현 이슈로 다시 쓸 때도 같다.
```

그다음 저장소 루트에서 `sh agent-rules/build.sh` 를 실행해 `AGENTS.md` 를 다시 만든다.

**`test_docs.py`**

- 템플릿 위치 단언을 고친다: `skills/spec/references/spec-template.md` 가 있고, `skills/handoff/references/`·`skills/relay/references/` 에는 없다.
- `skills/spec/SKILL.md` 가 있고, 머리말에 `disable-model-invocation` 이 없으며, 본문에 `relay_cli.py" handoff-check` 가 있다고 단언하는 테스트를 더한다.
- `SkillCallsExistingCommands`·`SupervisionStaysInOrca`·`OrcaGuideIsTheSource`·`Frontmatter` 가 보는 문서에 `skills/spec/` 아래 문서를 더한다.
- `relay:handoff` SKILL.md 의 「## 1. 구현 이슈를 쓴다」 절에 `relay:spec` 이 있다고 단언한다.

### 엣지 케이스

`human_todo` 의 입력 경우를 아래로 한정한다. 각 경우를 `test_handoff.py` 에 테스트 하나 이상으로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 코드 블록 안의 `머지 전:` 줄, 전각 콜론, 굵게 쓴 `**머지 전**:`). 범위 밖 경우의 결과는 테스트하지 않는다.

| # | 입력 | 결과 |
|---|---|---|
| 1 | 절이 없다 | 문제 「「사람이 할 일」 절이 없다」 |
| 2 | `- 머지 전: 없음`, `- 머지 뒤: 없음` | before `[]`, after `[]` |
| 3 | `- 머지 뒤: NAS 에 설치` (같은 줄 글) | after `["NAS 에 설치"]` |
| 4 | `- 머지 뒤:` + 하위 불릿 2개(체크박스 있음) | 체크박스를 뗀 항목 2개 |
| 5 | 4 + 둘째 항목 아래 더 깊은 번호 목록 | 항목 2개 (번호 줄은 세지 않는다) |
| 6 | `- 머지 뒤: 아래 둘` + 하위 불릿 2개 | 항목 3개 (`아래 둘` 포함) |
| 7 | 불릿 없이 `머지 전: 없음`·`머지 뒤: 없음` | 2 와 같다 |
| 8 | `*` 불릿 (`* 머지 전: 없음`) | 2 와 같다 |
| 9 | `- 머지 뒤:` 에 값도 하위 항목도 없음 (다음 줄이 빈 줄이거나 절 끝) | 문제 「`머지 뒤:` 에 값이 없다」 |
| 10 | `- 머지 뒤: <할 일>` (같은 줄 자리표시) | 문제 「`머지 뒤:` 에 자리표시(<…>)가 남아 있다」 |
| 11 | 하위 항목 글이 `<…>` 자리표시 | 10 과 같은 문제 |
| 12 | `- 머지 전: 없음` + 하위 불릿 | 문제 「`머지 전:` 이 `없음` 인데 하위 항목이 있다」 |
| 13 | `머지 전:` 줄이 없다 | 문제 「`머지 전:` 줄이 없다」 |
| 14 | `머지 뒤:` 줄이 2개다 | 문제 「`머지 뒤:` 줄이 2개다」 |
| 15 | 절 안 HTML 주석 속에 `- 머지 전: 없음` 이 있다 | 주석을 지운 뒤 읽는다 (주석 안 줄은 세지 않는다) |
| 16 | 절 안에 두 줄 말고 설명 문장이 있다 | 무시한다 |
| 17 | 본문 줄바꿈이 CRLF | LF 와 같은 결과 |

자리표시 판정: 앞뒤 공백을 뗀 글이 `<` 로 시작하고 `>` 로 끝나면 자리표시다. 문제 문자열은 표의 문구를 그대로 쓴다.

`check` 의 경우(테스트는 기존 `tracker()` 가짜 트래커로):

- 하위 이슈 없음 + 절 정상 → `human:I-<n>` ok, `human` 값 있음.
- 하위 이슈 없음 + 절 없음 → `human:I-<n>` fail, `human` 은 `None`, `exit_code` 1.
- 하위 이슈 있음 + 부모 절 정상 + 하위 이슈에 절 없음 → `human:<부모 ID>` ok.
- 하위 이슈 있음 + 부모에 절 없음 → `human:<부모 ID>` fail.
- 하위 이슈 있음 + 하위 이슈 하나에 절 있음 → `human-misplaced:<그 하위 ID>` fail(부모 절이 정상이어도).
- 다른 검사(`tasks`·`template:*`·`author:*`)가 실패해도 `human:*` 검사는 돈다(실패를 모아 한 번에 보고하는 기존 원칙).

### 에러 처리

- 이슈를 읽지 못하면 지금처럼 `IssueError`(CLI 종료코드 2). 「사람이 할 일」 문제는 `fail` 검사이지 입력 오류가 아니다.

## 기존 코드 참조

- `plugins/relay/scripts/relaylib/handoff.py:24` — `_section`: 절 읽기와 HTML 주석 제거. `human_todo` 도 이것을 쓴다.
- `plugins/relay/scripts/relaylib/handoff.py:71` — `check`: 실패를 모두 모아 돌려주는 구조. 새 검사도 같은 `_check` 모양으로 더한다.
- `plugins/relay/tests/test_handoff.py` — `tracker()` 가짜 트래커와 `GOOD` 본문 픽스처. 기존 픽스처 본문에 「사람이 할 일」 절을 더해 기존 테스트가 계속 통과하게 한다.
- `plugins/relay/skills/handoff/SKILL.md` 「## 1. 구현 이슈를 쓴다」 — `relay:spec` 으로 옮길 내용.
- `plugins/relay/tests/test_docs.py:102` — `test_handoff_runs_both_checks_and_creates_the_issue_worktree`: 템플릿 위치를 단언한다.
- `plugins/relay/tests/test_docs.py` `Frontmatter` — 스킬 머리말 YAML 검사.

## 인수 조건

- [ ] `handoff-check` 가 「사람이 할 일」 절이 없는 구현 이슈에 종료코드 1 을 낸다(하위 이슈가 있으면 부모를 본다).
- [ ] 하위 이슈에 「사람이 할 일」 절이 있으면 `human-misplaced:*` 가 `FAIL` 이다.
- [ ] 엣지 케이스 표 1~17 이 각각 테스트로 있다.
- [ ] `skills/spec/SKILL.md` 와 `skills/spec/references/spec-template.md` 가 있고, 템플릿의 「사람이 할 일」 절이 「인수 조건」 뒤에 있다. `skills/handoff/references/spec-template.md` 는 없다.
- [ ] `AGENTS.md` 에 `relay:spec` 호출 줄(wayfinder 문장 포함)이 있다.
- [ ] 게이트 명령: `python -m unittest discover -s plugins/relay/tests -q && sh agent-rules/build.sh --check` — 저장소 루트에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- `AGENTS.md` 를 손으로 고치는 것(`build.sh` 만 쓴다). 루트에 `CLAUDE.md` 를 만드는 것(`build.sh --check` 가 실패한다).
- 기존 테스트를 지우거나 단언을 약하게 고쳐 통과시키는 것. 픽스처 본문에 절을 더하는 것은 된다.
- `handoff.check` 의 기존 반환 키·검사 이름을 바꾸는 것.
- 테스트를 건너뛰게 만드는 것(`skip`, 조건부 `return`).

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
