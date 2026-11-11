> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/74
> updatedAt: 2026-11-11T02:31:11Z

# 리뷰 라운드 한도를 없애고 수정 라운드에서 같은 패턴을 함께 고치게 한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

relay 진행자 세션은 태스크마다 구현 라운드와 리뷰 라운드를 돌린다. 리뷰 결과 분기는 `relay_cli.py review-branch` 가 판정하고, 정본은 `plugins/relay/scripts/relaylib/review.py` 의 `decide()` 다. 지금은 구현 라운드 + 리뷰 라운드(총 라운드)가 `MAX_TOTAL_ROUNDS = 5` 를 넘으면 `{"action": "human", "reason": "total_round_limit"}` 을 내고, 진행자는 멈춤 보고를 남기고 끝난다.

결정([일괄 진행 한 번의 상한](https://github.com/hdmun/anything/issues/69)): 라운드 한도를 **모든 relay** 에서 없앤다. 구독은 정액이라 라운드를 더 써도 돈이 더 들지 않고, 한도로 멈추면 사람이 와야 해서 그쪽이 더 비싸다. 리뷰 루프는 리뷰 통과(`success`), `SPEC_VIOLATION`·`repeated_finding` 판정(`escalate`), 리포트 형식 위반(`rewrite`)으로만 갈린다. 워커 실패 규칙(기동 실패 circuit-break, `stopReason` 두 번째 멈춤, 판정 JSON 재검증 실패)은 그대로 남는다.

같은 결정에서 라운드가 길어진 원인 하나를 미리 막는다. 다른 저장소의 relay 실행 기록에서, 구현자가 지적된 자리만 고치고 같은 패턴이 있는 다른 자리를 그대로 두어 다음 라운드에 같은 지적이 문구만 바뀌어 다시 나온 사례가 2건 있었다. 그래서 수정 라운드 지시 두 곳에 「지적마다 같은 패턴을 변경 대상 파일 전체에서 찾아 함께 고친다」를 넣는다.

- 진행자가 구현 워커에 보내는 수정 라운드 본문: `skills/relay/references/review.md`
- 구현자 역할 파일의 템플릿: `templates/implementer.md.tmpl` 의 「수정 라운드」 절. 지금은 「그 파일에 적힌 지적만 고친다」라고 적혀 있다.

역할 파일 템플릿은 각 저장소에서 `/relay:init --force` 로 `.ai/roles/implementer.md` 를 다시 만들어야 반영된다. 그 일은 「relay 일괄 진행 구현」의 머지 뒤 할 일이다. 이 태스크는 템플릿만 고친다.

## 범위 밖 (건드리지 말 것)

- `MAX_TASKS`(`handoff.py`), `repeated_finding`·`spec_violation` 판정 규칙, `rewrite` 분기: 그대로 둔다.
- `review-branch` 출력의 `impl_rounds`·`review_rounds` 필드: 기록용으로 그대로 둔다.
- `plugins/relay/CONTEXT.md`(「총 라운드」 용어는 남긴다), `plugins/relay/docs/adr/`(이미 반영), `plugins/relay/README.md`(다른 이슈에서 고친다).
- 각 저장소의 `.ai/roles/` 생성 파일.
- 머지 재시도 한도: 머지 절차는 아직 없다(「relay 일괄 진행 구현」이 한도 없이 만든다).

## 변경 대상 파일

- `plugins/relay/scripts/relaylib/review.py` — 수정
- `plugins/relay/tests/test_review.py` — 수정
- `plugins/relay/skills/relay/references/review.md` — 수정
- `plugins/relay/skills/relay/references/stop.md` — 수정
- `plugins/relay/skills/relay/SKILL.md` — 수정
- `plugins/relay/templates/implementer.md.tmpl` — 수정
- `plugins/relay/tests/test_docs.py` — 수정

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```python
# plugins/relay/scripts/relaylib/review.py — 시그니처는 그대로다. 반환 action 에서 human 이 없어진다.
def decide(reviews_dir, task, impl_rounds, only=None):
    """→ {"action": "rewrite" | "success" | "escalate" | "fix_round", ...}"""
```

## 동작 명세

### 정상 경로

- `review.py`
  - `MAX_TOTAL_ROUNDS` 상수, `total` 계산, `human`/`total_round_limit` 분기, 모듈 docstring 의 `human` 줄을 지운다.
  - 나머지 분기 순서(`rewrite` → `success` → `escalate`(spec_violation) → `escalate`(repeated_finding) → `fix_round`)와 반환 필드는 그대로다.
- `test_review.py`
  - `test_total_round_limit_calls_human` 을 지운다.
  - 대신 "총 라운드가 6 이상(예: `impl_rounds` 3 + 리뷰 리포트 4개)이어도 마지막 리포트에 `BLOCKER` 만 있으면 `fix_round`" 테스트와 "같은 입력에서 SPEC_VIOLATION 이면 `escalate`" 테스트를 둔다.
  - `review_round_limit` 을 언급하는 주석이 있는 테스트는 한도 언급을 지운다(테스트 동작은 그대로).
- `review.md`
  - 「검증·심각도 분기·라운드 한도가 한 번에 나온다」 → 「검증·심각도 분기가 한 번에 나온다」.
  - 분기 표의 `human` 행을 지운다.
  - 「판정 규칙(심각도 우선순위, 반복 지적 비교, 라운드 한도)의 정본은」 → 「판정 규칙(심각도 우선순위, 반복 지적 비교)의 정본은」.
  - 「라운드 한도는 비용 상한이다.」 문장을 지운다.
  - 「수정 라운드는 구현 dispatch 에 `send` 한다」 1의 본문을 이렇게 바꾼다:
    `I-<n> 수정 라운드 N. 리뷰: .ai/reviews/I-<n>.rN.json / 원본 명세: .ai/specs/I-<n>-<슬러그>.md / base: <base> / 지적마다 같은 패턴을 변경 대상 파일 전체에서 찾아 함께 고친다.`
- `stop.md`
  - 트리거 표에서 「`review-branch`의 `human` — `total_round_limit`(총 라운드 5)」 행을 지운다.
  - 「시도와 라운드를 구분한다」의 「셋을 섞으면 예산이 엉뚱하게 깎인다.」 문장을 지운다.
  - 같은 절 표의 「총 라운드」 행에서 세는 법을 「위 둘의 합 (기록용, 한도 없음)」으로 바꾼다.
  - 「기동 실패는 환경 문제이고 구현자의 실력과 무관하므로 라운드 예산을 깎지 않는다.」 → 「기동 실패는 환경 문제이고 구현자의 실력과 무관하므로 라운드로 세지 않는다.」
- `SKILL.md` 불변식
  - 「spec 이 틀렸거나 spec 에 없는 결정이 필요하면, 그리고 라운드 한도·사람이 필요한 상황이면」 → 「spec 이 틀렸거나 spec 에 없는 결정이 필요하면, 그리고 사람이 필요한 상황이면」.
- `implementer.md.tmpl` 「## 수정 라운드」
  - 「그 파일에 적힌 지적만 고친다」 → 「그 파일에 적힌 지적을 고친다. 지적마다 같은 패턴을 spec 의 변경 대상 파일 전체에서 찾아 함께 고친다 — 지적된 자리만 고치면 같은 지적이 다음 라운드에 다른 자리에서 다시 나온다」.
  - 「리뷰 지적을 고치면서 다른 것까지 함께 손보지 않는다. 그 변경은 리뷰되지 않은 코드가 된다.」 → 「지적과 다른 종류의 문제는 손보지 않는다. 그 변경은 리뷰되지 않은 코드가 된다. 같은 패턴은 위대로 함께 고친다.」
  - `MINOR` 줄은 그대로 둔다.
- `test_docs.py`
  - relay 스킬 문서(`skills/relay/SKILL.md` + `references/*.md`)에 `total_round_limit`·`MAX_TOTAL_ROUNDS`·`라운드 한도` 가 없다고 단언하는 테스트를 더한다.
  - `scripts/relaylib/review.py` 에 `MAX_TOTAL_ROUNDS`·`total_round_limit` 이 없다고 단언한다.
  - `templates/implementer.md.tmpl` 과 `review.md` 에 「같은 패턴」이 있다고 단언한다.

### 엣지 케이스

- 리포트가 하나도 없으면 지금처럼 `ReviewError`.
- 총 라운드가 아무리 커도(예: `impl_rounds` 10 + 리포트 10개) 분기는 심각도와 반복 지적으로만 정해진다.
- `repeated_finding` 판정은 지금처럼 직전 리포트와 비교한다.
- 재개한 태스크의 `only` 필터(ADR 0010)는 그대로 동작한다.

### 에러 처리

- 바뀌지 않는다.

## 기존 코드 참조

- `plugins/relay/scripts/relaylib/review.py:121` — `decide`. `total` 과 `MAX_TOTAL_ROUNDS` 분기를 지울 곳.
- `plugins/relay/tests/test_review.py:187` — 지울 테스트.
- `plugins/relay/tests/test_roles.py` — 템플릿 렌더 테스트. 템플릿 문구를 바꿔도 통과해야 한다.
- `plugins/relay/tests/test_docs.py:51` — `test_severity_table_not_reintroduced`: 문서 문구 단언의 예.

## 인수 조건

- [ ] `review.py` 에 `MAX_TOTAL_ROUNDS`·`total_round_limit` 이 없다.
- [ ] 총 라운드 6 이상 + `BLOCKER` 입력에서 `decide` 가 `fix_round` 를 낸다(테스트).
- [ ] relay 스킬 문서에 라운드 한도 언급이 없다(`test_docs`).
- [ ] `review.md` 의 수정 라운드 본문과 `implementer.md.tmpl` 「수정 라운드」에 같은 패턴 지시가 있다.
- [ ] 게이트 명령: `python -m unittest discover -s plugins/relay/tests -q && sh agent-rules/build.sh --check` — 저장소 루트에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 한도를 다른 이름이나 다른 숫자로 다시 넣는 것.
- `repeated_finding` 비교를 느슨하게 하거나, 2라운드부터 리뷰 범위를 좁히는 것(기각된 안이다).
- 기존 테스트를 skip 하거나 단언을 약하게 고치는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
