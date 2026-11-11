---
name: relay
description: 'Orca orchestration 위에서 진행자(Claude)·구현자(agy)·리뷰어(codex)로 구현 이슈 하나를 PR 까지 옮기는 진행자 세션의 스킬이다. 워커 dispatch, 게이트 재검증, 리뷰 심각도 분기, PR 생성까지를 다룬다. 기동 줄이 "relay: 구현 이슈 <URL>" 인 진행자 세션으로 떴을 때, 그리고 사람이 relay 로 구현 이슈를 진행하라고 할 때 쓴다. 구현 이슈를 진행자에게 넘기는 일은 `relay:handoff` 다. 작업을 다른 워크트리나 에이전트에 통째로 넘기는 단순 위임(감독·리뷰 없이 맡기기)에는 쓰지 않는다.'
---

# relay

`relay`는 3개 AI 코딩 에이전트를 Orca orchestration 위에서 연결하는 파이프라인의 **진행자 세션** 스킬이다.

## 진입

**진행자 세션은 설계 세션이 `relay:handoff` 로 띄운다**(ADR 0005). 기동 줄은 `relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그>` 이고, 이 세션은 그 이슈의 **이슈 워크트리** 안에서 Run 을 소유한 최상위 코디네이터다. dispatch 된 워커가 아니다. 먼저 `references/start.md`를 Read 한다.

- **호환 한 줄**: 입력이 T-NNN spec 경로(`.ai/specs/T-…`)이거나 Task 첫 줄이 `relay 진행자:` 이면 진행하지 않는다. "3.0.0 은 구현 이슈만 받는다. spec 을 이슈로 옮기고 `relay:handoff` 로 시작한다" 를 남기고 멈춘다.
- 사람이 이 세션에서 직접 "relay 로 이슈 <URL> 진행해줘" 라고 해도 같다. 이슈 워크트리 밖이면 진행하지 않고 `relay:handoff` 로 시작하라고 알린다 — 이슈 워크트리는 handoff 가 만든다.

## 역할과 모델

| 역할 | 실행 주체 | 모델 계열 / effort | Orca에서의 위치 |
|---|---|---|---|
| 설계자 | Claude Code | Opus (`/model opus`) / high | 설계 세션 — 구현 이슈를 쓰고 `relay:handoff` 후 끝난다. Run 밖 |
| 진행자 | Claude Code | Opus / low — `model coordinator` 를 handoff 가 기동 인자로 준다 | 진행자 세션 — Run 을 소유한 코디네이터 |
| 구현자 | agy (Antigravity CLI) | agy 기본 모델 — (d) 참조 | supervised worker (깊이 1) |
| 리뷰어 | codex | 모델 설정 파일의 `reviewer.model` (필수) / high | supervised worker (깊이 1) |
| 판정 | Claude Code 서브에이전트 | Opus / high — `model judge` 를 Agent 도구 인자로 준다 | 진행자의 일회성 서브에이전트 (Orca 밖) |

**이 스킬은 모델 버전을 적지 않는다.** 위 표는 **기본값**(모델 계열)이고, 사용자가 정하는 값은 설정 파일에 있다. 실제로 쓰인 버전은 커밋 트레일러(`Implemented-by:`, `Reviewed-by:`)에 사후로 남긴다.

모델·effort 설정 파일의 형식, 우선순위, 역할별 규칙은 `references/models.md`에 있다. 그 파일을 Read 한 뒤 `relay_cli.py models`에 묻는다.

## 파이프라인 흐름

```
[설계 세션 Opus·high]   구현 이슈 작성 → relay:handoff (doctor + handoff-check → 이슈 워크트리 + 진행자) → 끝
                               ↓ worktree create --agent claude
[진행자 세션 Opus·low]  doctor · 기준선 게이트 · run-create · 태스크 DAG
                        태스크마다(순차): spec 스냅숏 → 구현 워커 기동
                               ↓ worker-start --worktree current
[구현 agy]             구현 + 자체 게이트 루프
                               ↓
[진행자 세션]           게이트 독립 재검증 → 구현 커밋
                               ↓
[리뷰 codex·high]      .ai/reviews/I-<n>.rN.json 작성
                               ↓
[진행자 세션]           스키마 검증 → 심각도 분기 → 다음 태스크
                        모든 태스크 뒤: PR 하나 (구현 이슈마다) → 사람에게 보고
```

## 불변식

모든 경로에 적용된다. 아래 단계 파일을 읽은 뒤에도 이 규칙이 우선한다.

- orca 명령을 쓰기 전에 **Skill 도구로 Orca 스킬 `orchestration`·`orca-cli` 를 불러** Orca 가이드를 읽는다. relay 문서는 명령 문법을 적지 않는다(ADR 0003).
- 워커(구현자·리뷰어)는 모두 `worker-start --agent`로, **`--worktree current`**(이슈 워크트리)로 띄운다. model·effort는 `model <역할>` 결정기 값을 `--model`·`--effort`로 준다. 워크트리를 새로 만들지 않는다(ADR 0010).
- 게이트는 종료코드로 판정한다. 통과하면 즉시 구현 커밋을 만든다.
- `<base>`는 spec과 리뷰 Task에 명시한다. 각 태스크의 `<base>`는 그 태스크의 스냅숏 커밋 직후의 HEAD다.
- 머지는 사람이 한다(자동 머지 금지). PR 은 구현 이슈마다 하나, 모든 태스크가 끝난 뒤에 연다(ADR 0007).
- 진행자는 구현 이슈를 고치지 않는다. 스냅숏만 읽는다(ADR 0006).
- 감독은 Orca의 깨우기와 영수증을 따른다(ADR 0009). relay가 더하는 감독 정책은 아래 세 줄뿐이다.
  - **`agent_prompt_blocked`면 사람을 부른다.** 워커의 확인창·프롬프트(업데이트·trust·승인)는 사람이 그 워커 터미널에서 직접 처리한다(자동 응답 금지). 진행자는 키를 보내지 않고, 보낼 키를 선택지로 묻지도 않는다 — 사람에게 알리고 기다린다. 'Skip'처럼 안전해 보이는 선택도 사람이 고르고 사람이 누른다. 알려진 확인창의 예방책은 `doctor`가 검사한다.
  - **`outcome_unknown`이면 스스로 재출발하지 않는다.** 워커는 `worker-keep-open`으로 남기고 **멈춤 보고 후 끝난다** — (h). 입력이 늦게 도착하면 같은 Task를 두 워커가 하게 된다. 사람의 판단을 이 세션에서 기다리지 않는다 — 다시 시작하는 것은 사람이 같은 이슈로 handoff 할 때다.
  - **워커의 `escalation`에 `stopReason`이 있으면** spec의 해당 절을 근거로 `send`로 한 번 다시 지시한다. 같은 워커가 두 번째로 멈추면 사람이 필요한 것으로 (h). 다시 지시는 라운드로 세지 않는다.
- **진행자는 spec 을 스스로 해석하지 않는다.** SPEC_VIOLATION·반복 지적·spec 해석 질문은 **판정 서브에이전트**에 맡기고, 판정은 spec 안에서만 한다. spec 이 틀렸거나 spec 에 없는 결정이 필요하면, 그리고 사람이 필요한 상황이면 **멈춤 보고**를 남기고 끝난다 — (h). 진행자는 구현 이슈를 고치지 않는다(ADR 0008). decision gate는 쓰지 않는다.
- `relay_cli` 결정기는 stdout JSON 한 줄의 `action`대로 행동한다. 검사기는 종료코드 0 통과 / 1 실패 / 2 입력 오류다. `$RELAY`는 이 스킬을 불러왔을 때 표시되는 *Base directory*에서 두 단계 위(플러그인 루트)다 — `python "$RELAY/scripts/relay_cli.py" --help`.
- Orca 가이드와 충돌하면 Orca 가이드가 옳다. relay 문서를 고친다. 일부러 다르게 하는 것은 아래 「Orca 기본과 다른 점」에만 둔다.
- references Read가 "파일 없음"으로 실패하면 플러그인이 갱신된 것이다. `/reload-plugins` 후 처음 Read 한 단계 파일부터 다시 한다.

## Orca 기본과 다른 점

Orca 가이드의 기본 경로와 일부러 다르게 하는 것은 여기에만 적는다. 항목마다 근거가 있고, 근거가 사라지면 항목을 지운다. 이슈 워크트리를 만들 때의 차이(`--base-branch main` 등)는 `relay:handoff` 의 표에 있다.

| relay 가 하는 것 | Orca 기본 | 근거 |
|---|---|---|
| 워커의 `worker_done` 보고를 믿지 않고 게이트를 진행자가 다시 돌린다 | 정착 보고를 받아 다음으로 간다 | 구현자는 게이트를 약화시키거나 사각지대에서 "통과"를 보고할 수 있다 — (f) |
| 리뷰어는 라운드마다 새 워커로 띄운다 | 정착한 워커에 `send` 해 후속 Task 로 다시 연다 | 이전 리뷰의 맥락에 끌려가지 않게 한다 — (g). 구현자는 Orca 기본대로 `send` 로 다시 연다 |
| `worker-start` 영수증을 `--full` 로 받는다 | 간결 보기 | 커밋 트레일러의 모델명(`launch.effective.model`)이 전체 기록에만 있다(Orca 1.4.247+). `--full` 은 `ready` 가 아니면 종료코드 1이다 — 판정은 종료코드가 아니라 영수증의 `state` 로 한다 |

## 단계 목록

각 단계에 들어서면 먼저 해당 파일을 Read 한다. 읽기 전에는 그 단계를 판정하지 않는다.

| 단계 | 하는 일 | 먼저 Read 할 파일 |
|---|---|---|
| 시작 (c) | Orca 스킬, doctor, 기준선 게이트, Run·태스크 DAG, 태스크마다 spec 스냅숏 | `references/start.md` |
| 구현 워커 (d) | 예열·`worker-start --agent`·영수증 | `references/implementer.md` |
| 리뷰 워커 (d) | model reviewer·diff-guard·`worker-start --agent` | `references/reviewer.md` |
| 대기 (e) | 턴을 끝내고 Orca가 깨우면 메시지를 처리한다 | 아래 (e) |
| 게이트 (f) | 독립 재검증, 통과 즉시 커밋 | `references/gate.md` |
| 리뷰 분기 (g) | review-branch, 수정 라운드 | `references/review.md` |
| 판정·멈춤 (h) | 판정 서브에이전트, 판정 기록, 멈춤 보고, 시도와 라운드 | `references/stop.md` |
| 종료 (i) | 워커 출구, PR(경로 A/B), 사람에게 보고 | `references/finish.md` |

예외 경로는 해당 상황에서만 읽는다.

- 변이 테스트 게이트 → `references/gate-mutation.md`

## (e) 대기 — Orca가 깨운다

워커를 띄운 뒤 턴을 끝낸다. Orca가 `worker_done`·`escalation`·`question`으로 진행자를 깨운다. 폴링하지 않는다 — 조용한 워커는 relay가 판정하지 않고 사람이 Orca UI로 본다(ADR 0009). 메시지 처리 순서(`reply`·ack)는 Orca 가이드를 따른다.

- `worker_done` → 구현이면 (f), 리뷰면 (g).
- `escalation` → 불변식의 `stopReason` 줄. `stopReason`이 없으면 (h).
- `question` → spec 해석이나 범위 판단이 필요한 질문은 진행자가 답을 짓지 않고 판정 서브에이전트에 맡긴다 — (h). spec 해석이 아닌 질문(절차·도구)만 직접 답하고, **판단의 근거까지 적는다** — 워커는 spec과 역할 파일만 알고 이 대화를 모르므로, 어느 spec 항목에 근거했는지, 그 발견을 finding으로 올릴지까지 함께 지시한다.

## (j) 컨텍스트 위생 규범

1. **`orca ... --json` 출력에서 필요한 필드만 추출해서 읽는다.** orca의 JSON 응답은 크고, 매 턴 재전송되어 비용이 누적된다.
2. 진행자 한 명이 이슈의 태스크를 모두 돈다(ADR 0005). 그래서 태스크가 5개 이하다. 지난 태스크의 게이트 로그·리뷰 리포트는 다시 읽지 않는다 — 필요한 것은 git 과 `.ai/reviews/` 에 있다.
3. 태스크 상태는 `task-list --ready`로 매번 조회한다. 컨텍스트에 들고 있지 않는다.

## (k) 병렬 실행 정책

현재는 **순차 실행**이다. 단 `task-create --deps`로 DAG는 처음부터 정의한다 —
나중에 병렬로 전환할 때 태스크 정의를 고치지 않고 실행 정책만 바꾸면 되게 하기 위해서다.
승격 기준은 **연속 5개 태스크가 멈춤 보고 없이 통과**하는 것이다.
의존 사슬은 3~4단계를 넘기지 않는다(Orca 가이드 권고).

## 왜 진행자를 따로 띄우는가

Claude Code는 매 턴 전체 컨텍스트를 재전송하므로 비용은 (컨텍스트 크기 × 턴 수)에 비례한다.
진행 루프는 태스크당 10~20턴인데 판단 함량이 거의 없다(대부분 조건 분기).
반면 설계·명세는 턴 수가 적고 판단 함량이 최대다.
따라서 잦고 긴 구간은 effort 가 낮은 진행자 세션에, 드물고 짧은 구간은 effort 가 높은 설계 세션에 둔다. 설계 세션은 handoff 뒤 끝나므로 진행 루프의 컨텍스트를 받지 않는다. 역할별 값은 모델 설정 파일에서 바꾼다.

## 이 스킬 자체를 고칠 때

> **이 스킬 자체를 고칠 때**: 소스의 정본은 `scripts` 저장소의 `plugins/relay/` 이고, 설치본은 Claude Code가
> `plugins/cache/hdmun-scripts/relay/<version>/` 에 버전 경로로 두는 관리 복사본이다. 직접 고치지 않는다.
> 소스를 고친 뒤 `plugin.json` 의 `version` 을 올리고 `claude plugin update relay` 를 설정 디렉터리마다 실행한다.
>
> **저장소 쪽 역할 파일**(`.ai/roles/`)은 이 플러그인의 `templates/` 가 역할 파일의 정본이다. 저장소에서 `/relay:init` 으로
> 생성하고, 플러그인을 업데이트한 뒤에는 `/relay:init --check` 로 드리프트를 확인한다(종료코드 1이면 드리프트).
> **역할 파일을 손으로 고치지 않는다** — 공유 규범은 `templates/` 를, 저장소 고유분은 `.ai/relay-roles.json` 을 고친다.
