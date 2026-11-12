> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/77
> updatedAt: 2026-11-11T02:31:20Z

# batch-plan: 진행 목록을 만들고 모든 이슈를 검사한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

relay 일괄 진행은 사람이 구현 이슈 URL 하나로 시작한다. 시작 스킬 `relay:batch`(이 이슈의 다른 태스크)는 이 태스크가 만드는 검사기 `relay_cli.py batch-plan --issue <URL>` 을 돌리고, `FAIL` 이 하나라도 있으면 아무 이슈도 시작하지 않는다. 재개도 같은 명령이다. 멈춘 뒤 사람이 시작 명령을 다시 치면 진행 목록을 그때 새로 만든다.

**진행 목록** 규칙(결정 [#57](https://github.com/hdmun/anything/issues/57)·[#58](https://github.com/hdmun/anything/issues/58)·[#59](https://github.com/hdmun/anything/issues/59)):

- 맡긴 구현 이슈에서 출발해 GitHub 이슈 의존(blocking)을 **양방향으로** 따라가고, 이어진 **열린** 이슈를 모두 모은다.
- 닫힌 이슈는 목록에 넣지 않는다. 하지만 **탐색은 닫힌 이슈를 지나간다**. 예: 12 닫힘, 12 가 14·15 를 막음, 14 의 URL 로 시작 → 12 를 지나 15 를 찾는다 → 목록 [14, 15]. 끊으면 15 가 알림 없이 돌지 않는다.
- 순서는 위상 정렬(막는 이슈가 앞)이고, 동률이면 이슈 번호가 작은 것부터다.
- 같은 저장소 이슈만 쓴다. 다른 저장소 이슈와 이어져 있으면 시작하지 않는다.
- 하위 이슈(태스크)의 blocking 은 자기 구현 이슈 안(형제 하위 이슈끼리)에서만 쓴다. 밖을 가리키면 시작하지 않는다.
- 목록의 모든 이슈에 기동 전 검사(`handoff.check`, 「사람이 할 일」 절 포함)를 돈다. 하나라도 실패하면 시작하지 않는다.
- 「사람이 할 일」의 `머지 전:` 에 할 일이 있는 이슈가 하나라도 있으면 시작하지 않는다.

GitHub API 사실(이 저장소에서 확인, gh 2.96):

- `gh api repos/<o>/<r>/issues/<n>/dependencies/blocked_by` 와 `…/dependencies/blocking` → 이슈 객체 배열. 항목에 `number`, `state`(`open`|`closed`), `html_url`, `repository_url` 이 있다.
- `gh api repos/<o>/<r>/issues/<n>` → `state`, `parent_issue_url`(하위 이슈면 부모의 API URL, 아니면 `null`), `title`, `body`, `author_association`.
- 하위 이슈 목록은 기존 `handoff.sub_issues` 가 읽는다.

이 태스크는 「relay 일괄 진행 준비」에서 바뀐 `handoff.check`(반환값 `human`)를 쓴다.

## 범위 밖 (건드리지 말 것)

- 살아 있는 진행자 세션 검사(Orca 워크트리·터미널): `relay:batch` 스킬의 단계다(다른 태스크).
- 머신 점검(`doctor`): `relay:batch` 가 따로 한 번 돌린다.
- 머지, handoff, 문서.
- local-markdown 이슈: 일괄 진행은 GitHub 이슈만 받는다.
- `handoff.check` 의 검사 규칙 자체.

## 변경 대상 파일

- `plugins/relay/scripts/relaylib/batch.py` — 신규
- `plugins/relay/scripts/relaylib/issue.py` — 수정 (`fetch` 반환값에 `state`·`parent`)
- `plugins/relay/scripts/relay_cli.py` — 수정
- `plugins/relay/tests/test_batch.py` — 신규
- `plugins/relay/tests/test_issue.py` — 수정 (`fetch` 의 새 키 테스트)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```
python relay_cli.py batch-plan --issue <구현 이슈 URL> [--json]     (검사기 — 일괄 진행 시작 검사)
```

```python
# plugins/relay/scripts/relaylib/batch.py
def plan(issue_ref, run):
    """구현 이슈 → {"order": [{"number": n, "url": u, "title": t}], "checks": [...], "field": "일괄 진행: #a #b"}.
    시작 이슈를 읽지 못하거나 local-markdown 참조면 issue.IssueError."""

def exit_code(checks):
    """FAIL 이 하나라도 있으면 1, 아니면 0."""

# plugins/relay/scripts/relaylib/issue.py — fetch 의 반환 dict 에 두 키를 더한다(기존 키는 그대로)
#   "state":  "open" | "closed"            local-markdown 은 늘 "open"
#   "parent": 부모 이슈 번호(int) 또는 None  parent_issue_url 의 마지막 마디. local-markdown 은 None
```

텍스트 출력(`--json` 없음):

```
진행 목록: #12 #14 #15
<검사 줄들 — 기존 _print_checks 형식>
기동 줄 필드: / 일괄 진행: #12 #14 #15
```

- 목록이 비면 첫 줄은 `진행 목록: 없음` 이고 필드 줄은 뺀다.
- `--json` 이면 `plan()` 결과를 JSON 한 줄로 낸다.
- 종료코드: FAIL 이 있으면 1, 없으면 0, 입력 오류는 2(ADR 0001 검사기 규약).

## 동작 명세

### 정상 경로

1. `issue.parse` 로 참조를 읽는다. GitHub 이 아니면 `IssueError`. 시작 이슈를 `fetch` 한다(실패하면 `IssueError`).
2. 시작 이슈에 `parent` 가 있으면 `start` 검사 FAIL 「#n 은 하위 이슈(태스크)다 — 부모 구현 이슈 URL 로 시작한다」. 탐색하지 않고 결과를 돌려준다.
3. 너비 우선 탐색: 방문한 이슈마다 `blocked_by`·`blocking` 을 읽는다(`gh api --paginate`). 이웃마다:
   - `html_url` 의 owner/repo 가 시작 이슈와 다르면 `repo:#<지금 이슈>` FAIL 「#n 이 다른 저장소 이슈 <owner>/<repo>#<m> 와 blocking 으로 이어져 있다」. 따라가지 않는다.
   - 같은 저장소면 방문 대상에 넣는다(닫힌 이슈도 넣는다).
   - 간선을 기록한다. `blocked_by` 응답은 「이웃이 지금 이슈를 막음」, `blocking` 응답은 「지금 이슈가 이웃을 막음」이다.
4. 방문한 이슈 중 열린 이슈마다 `fetch` 한다. 열린 이슈에 `parent` 가 있으면 `task-edge:#n` FAIL 「열린 하위 이슈 #n 이 진행 목록에 이어졌다 — 하위 이슈의 blocking 은 자기 구현 이슈 안에서만 쓴다」. 그 이슈는 목록에서 뺀다.
5. 위상 정렬: 방문한 **모든** 이슈(닫힌 이슈 포함)와 간선으로 Kahn 알고리즘을 돌린다. 준비된 이슈가 여럿이면 번호가 작은 것부터 꺼낸다. 순환이 있으면 `list` FAIL 「blocking 순환: #a #b …」. 정렬 결과에서 열린 이슈(4 에서 뺀 이슈 제외)만 남긴 것이 `order` 다.
6. `order` 가 비면 `list` FAIL 「열린 구현 이슈가 없다」. 아니면 `list` ok 「N개: #a #b」.
7. `order` 의 이슈마다:
   - `handoff.check(url, run)` 의 검사들을 이름 앞에 `#<n> ` 을 붙여 더한다(예: `#12 template:I-13`). `IssueError` 면 `read:#n` FAIL 을 더하고 다른 이슈는 계속 검사한다.
   - 그 이슈의 하위 이슈마다 `blocked_by`·`blocking` 이웃이 모두 같은 부모의 하위 이슈인지 본다. 아니면 `task-edge:#<부모>` FAIL 「태스크 #s 가 구현 이슈 밖의 #x 와 blocking 으로 이어져 있다」.
   - `handoff.check` 결과의 `human` 이 있고 `before` 가 비어 있지 않으면 `before-merge:#n` FAIL 「「사람이 할 일」 `머지 전:` 에 할 일 N개 — 일괄 진행은 시작하지 않는다」, fix 「지금 하고 `없음` 으로 고치거나, `머지 뒤:` 로 옮기거나, 그 이슈를 relay:handoff 로 따로 돌린다」.
8. `field` 는 `일괄 진행: ` 뒤에 `order` 의 `#번호` 를 공백으로 이은 것이다.

### 엣지 케이스

입력 경우를 아래로 한정한다. 경우마다 가짜 `run`(gh api 응답을 흉내 냄)으로 테스트 하나 이상을 둔다. **열거하지 않은 경우는 범위 밖이다.**

| # | 그래프 (A → B 는 A 가 B 를 막음) | 시작 | 결과 |
|---|---|---|---|
| 1 | 12 혼자 | 12 | order [12], FAIL 없음 |
| 2 | 12 → 14 → 15 | 12 | [12, 14, 15] |
| 3 | 2 와 같음 | 14 | [12, 14, 15] (양방향) |
| 4 | 12(닫힘) → 14, 12 → 15 | 14 | [14, 15] (닫힌 12 를 지나 15) |
| 5 | 12(닫힘) → 14 → 15 | 14 | [14, 15] (재개: 머지된 12 가 빠진다) |
| 6 | 12 → 20, 12 → 15 (20·15 사이 간선 없음) | 12 | [12, 15, 20] (동률은 번호 순) |
| 7 | 12 → 14(닫힘) → 15 | 12 | [12, 15] (닫힌 이슈를 지난 순서도 지킨다) |
| 8 | 12 → 다른 저장소 이슈 | 12 | `repo:#12` FAIL |
| 9 | 12 → 30, 30 은 열린 하위 이슈 | 12 | `task-edge:#30` FAIL, order 에 30 없음 |
| 10 | 12 의 하위 이슈 13 → 40 (40 은 12 의 하위 이슈가 아님) | 12 | `task-edge:#12` FAIL |
| 11 | 12 의 하위 이슈 13 → 14 (14 는 12 의 하위 이슈) | 12 | `task-edge` FAIL 없음 |
| 12 | 12 → 14 → 12 (순환) | 12 | `list` FAIL |
| 13 | 시작 이슈가 하위 이슈 | 13 | `start` FAIL |
| 14 | 12(닫힘) 혼자 | 12 | `list` FAIL 「열린 구현 이슈가 없다」 |
| 15 | 2 + 14 의 `머지 전:` 에 1개 | 12 | `before-merge:#14` FAIL, 12·15 도 검사됨 |
| 16 | 2 + 15 의 본문에 템플릿 필수 절이 없음 | 12 | `#15 template:I-15` FAIL, 12·14 도 검사됨 |
| 17 | 2 + 14 를 읽지 못함(gh 실패) | 12 | `read:#14` FAIL |
| 18 | 시작 참조가 local-markdown 경로 | — | 입력 오류(종료코드 2) |

### 에러 처리

- 시작 이슈를 읽지 못함, 참조 형식 오류, local-markdown → `IssueError` → 종료코드 2.
- 시작 이슈가 아닌 이슈의 의존 API·이슈 읽기가 실패하면 `read:#n` FAIL 로 모으고 계속한다.

## 기존 코드 참조

- `plugins/relay/scripts/relaylib/handoff.py:57` — `sub_issues`: `gh api` 로 하위 이슈를 읽는 방식.
- `plugins/relay/scripts/relaylib/handoff.py:71` — `check`: `batch.plan` 은 이것을 그대로 부른다.
- `plugins/relay/scripts/relaylib/issue.py:42` — `fetch`: `state`·`parent` 를 더할 곳.
- `plugins/relay/scripts/relay_cli.py:367` — `cmd_handoff_check`: 검사기 출력(`_print_checks`)과 종료코드.
- `plugins/relay/tests/test_handoff.py` — `tracker()`: 가짜 `gh api` 응답. 의존 API 경로(`/dependencies/blocked_by`, `/dependencies/blocking`)도 같은 방식으로 흉내 낸다.

## 인수 조건

- [ ] 엣지 케이스 표 1~18 이 각각 테스트로 있다.
- [ ] 재개 경로: 닫힌 이슈를 거쳐 진행 목록을 다시 만들고 닫힌 이슈는 뺀다(표 4·5·7 의 테스트).
- [ ] `relay_cli.py batch-plan` 이 FAIL 이 있으면 종료코드 1, 없으면 0 을 낸다(`relay_cli.main` 을 가짜 `run` 으로 부르는 테스트).
- [ ] `issue.fetch` 가 `state`·`parent` 를 돌려준다(GitHub·local-markdown 각각 테스트).
- [ ] 게이트 명령: `python -m unittest discover -s plugins/relay/tests -q && sh agent-rules/build.sh --check` — 저장소 루트에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 실제 GitHub 을 부르는 테스트.
- 닫힌 이슈를 목록에 넣는 것, 닫힌 이슈에서 탐색을 멈추는 것.
- 첫 FAIL 에서 멈추는 것(실패는 모두 모아 한 번에 보고한다).
- `handoff.check` 의 검사 규칙을 `batch.py` 에 다시 구현하는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
