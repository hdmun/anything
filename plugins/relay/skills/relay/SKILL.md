---
name: relay
description: Orca orchestration 위에서 설계자·진행자(Claude)·구현자(agy)·리뷰어(codex) 4역할 파이프라인을 굴릴 때 사용한다. spec 작성부터 워커 dispatch, 게이트 재검증, 리뷰 심각도 분기, PR 생성까지를 다룬다. "relay", relay Run 감독, T-NNN spec 설계를 요청할 때, 그리고 Task 첫 줄이 "relay 진행자:" 인 Orca 워커로 떴을 때 쓴다. 작업을 다른 워크트리나 에이전트에 통째로 넘기는 단순 위임(handoff — 감독·리뷰 없이 맡기기)에는 쓰지 않는다.
---

# relay

`relay`는 3개 AI 코딩 에이전트를 Orca orchestration 위에서 연결하는 파이프라인의 코디네이터 스킬이다.

## 진입 약속과 세션 판정

**사람은 첫 요청에 "relay"를 명시해 이 스킬을 부른다.** 예: "relay로 T-NNN 설계해줘", "relay Run `<id>` 이어서 감독해줘". 그 세션이 **설계 세션**이다.
**진행자 워커**는 설계 세션이 태스크마다 띄운다. Task spec 첫 줄 `relay 진행자: Run <run_id> / T-NNN`이 워커 안에서 이 스킬을 부른다.

**판정 기준은 Orca preamble 하나다** — Orca 가이드의 역할 판정과 같다(ADR 0004).

- 프롬프트에 Orca가 주입한 preamble(`You are a dispatched worker`, Task ID·Dispatch ID가 박힌 `worker_done` 명령, `=== TASK ===` 블록)이 있으면 **진행자 워커**다 → 먼저 `references/start.md`를 Read 한다.
- 없으면 **설계 세션**이다 → 먼저 `references/design.md`를 Read 한다. 사람이 Run ID를 주며 "진행해줘"라고 해도 preamble이 없으면 설계 세션이다 — 그 Run을 `run-use`로 이어 받아 감독하고, 태스크 진행은 진행자 워커에게 맡긴다.

| 구분 | 설계 세션 | 진행자 워커 |
|---|---|---|
| 누가 여는가 | 사람 (relay 호출) | 설계 세션이 `worker-start --agent claude`로 (`model coordinator`) |
| 하는 일 | spec 작성, run/task 생성, ready 태스크마다 진행자 워커 기동·감독, 진행자의 `ask`에 답하거나 사람에게 넘김, 심각도 판단(SPEC_VIOLATION 등) | 태스크 하나: 워크트리·기준선, 하위 워커(구현자·리뷰어) 기동, 대기, 게이트 재검증, 리뷰 분기, PR 생성 |
| 끝나는 지점 | Run의 태스크가 모두 정착했을 때. 컨텍스트가 커지면 새 세션에서 `run-use`로 이어 간다 | 태스크 하나를 `worker_done`으로 보고했을 때. 해제는 설계 세션이 한다 |
| Orca에서의 위치 | Run을 소유한 코디네이터 | 설계 세션의 워커이자, 구현자·리뷰어의 코디네이터 |
| 사람과의 대화 | 유일한 창구 | 없다. 묻는 것은 모두 `ask`로 설계 세션에 |
| 판단 함량 | 최대 (새 개념, 되돌리기 어려운 결정) | 최소 (대부분 조건 분기) |

## 역할과 모델

| 역할 | 실행 주체 | 모델 계열 / effort | Orca에서의 위치 |
|---|---|---|---|
| 설계자 | Claude Code | Opus (`/model opus`) / high | 코디네이터 자신 (워커 아님) — 설계 세션 |
| 진행자 | Claude Code | Opus / low — `model coordinator` 가 `worker-start` 인자로 준다 | supervised worker, 태스크마다 새로 띄우고 해제 — 진행자 워커 |
| 구현자 | agy (Antigravity CLI) | agy 기본 모델 — (d) 참조 | supervised worker |
| 리뷰어 | codex | 모델 설정 파일의 `reviewer.model` (필수) / high | supervised worker |

**이 스킬은 모델 버전을 적지 않는다.** 위 표는 **기본값**(모델 계열)이고, 사용자가 정하는 값은 설정 파일에 있다. 실제로 쓰인 버전은 커밋 트레일러(`Implemented-by:`, `Reviewed-by:`)에 사후로 남긴다.

모델·effort 설정 파일의 형식, 우선순위, 역할별 규칙은 `references/models.md`에 있다. 그 파일을 Read 한 뒤 `relay_cli.py models`에 묻는다.

## 파이프라인 흐름

```
[설계 세션 Opus·high]  /grill-with-docs  (발동 기준은 (b) 참고)
                         ├─ CONTEXT.md 갱신
                         └─ ADR 추가 (해당 시)
                       .ai/specs/T-NNN.md 작성
                       run-create / task-create --deps
                       ready 태스크마다(순차): 진행자 워커 기동 → 대기·question 에 답 → worker_done 확인 → release
                               ↓ worker-start --agent claude
[진행자 워커 Opus·low]   preamble 의 Task → 워크트리·기준선 → 구현 워커 기동
                               ↓
[구현 agy]             구현 + 자체 게이트 루프
                               ↓
[진행자 워커]           게이트 독립 재검증
                               ↓
[리뷰 codex·high]      .ai/reviews/T-NNN.rN.json 작성
                               ↓
[진행자 워커]           스키마 검증 → 심각도 분기 → PR 생성 → 하위 워커 정리 → worker_done
```

## 불변식

모든 경로에 적용된다. 아래 단계 파일을 읽은 뒤에도 이 규칙이 우선한다.

- orca 명령을 쓰기 전에 **Skill 도구로 Orca 스킬을 불러** Orca 가이드를 읽는다 — 설계 세션은 `orchestration`, 진행자 워커는 `orchestration`·`orca-cli`. relay 문서는 명령 문법을 적지 않는다(ADR 0003).
- 워커(진행자·구현자·리뷰어)는 모두 `worker-start --agent`로 띄운다. model·effort는 `model <역할>` 결정기 값을 `--model`·`--effort`로 준다. 같은 터미널을 다시 쓰는 수정 라운드만 `--terminal`이다.
- 게이트는 종료코드로 판정한다. 통과하면 즉시 구현 커밋을 만든다.
- `<base>`는 spec과 리뷰 Task에 명시한다.
- 머지는 사람이 한다(자동 머지 금지). 확인창·프롬프트는 사람을 부른다(자동 응답 금지).
- 진행자 워커는 혼자 판단할 수 없는 것(SPEC_VIOLATION, 반복 지적, 라운드 한도, 사람이 필요한 상황)을 **모두 `ask`로 설계 세션에 묻는다.** 사람 호출도 이 `ask`이고, 설계 세션이 사람에게 전한다. decision gate는 쓰지 않는다.
- `relay_cli` 결정기는 stdout JSON 한 줄의 `action`대로 행동한다. 검사기는 종료코드 0 통과 / 1 실패 / 2 입력 오류다. `$RELAY`는 이 스킬을 불러왔을 때 표시되는 *Base directory*에서 두 단계 위(플러그인 루트)다 — `python "$RELAY/scripts/relay_cli.py" --help`.
- Orca 가이드와 충돌하면 Orca 가이드가 옳다. relay 문서를 고친다. 일부러 다르게 하는 것은 아래 「Orca 기본과 다른 점」에만 둔다.
- references Read가 "파일 없음"으로 실패하면 플러그인이 갱신된 것이다. 설계 세션은 `/reload-plugins` 후 처음 Read 한 단계 파일부터 다시 한다. 진행자 워커는 사람이 필요한 것으로 `ask` 한다.

## Orca 기본과 다른 점

Orca 가이드의 기본 경로와 일부러 다르게 하는 것은 여기에만 적는다. 항목마다 근거가 있고, 근거가 사라지면 항목을 지운다.

| relay 가 하는 것 | Orca 기본 | 근거 |
|---|---|---|
| 진행자 워커는 `--model`·`--effort` 를 늘 준다 (`model coordinator`, 설정이 없으면 `opus`/`low`) | 사용자가 모델을 고르지 않았으면 생략해 기본 모델을 물려받는다 | 잦고 긴 진행 루프는 effort 를 낮춰 둔다 — 생략하면 사용자 기본 effort 로 뜬다. `--effort` 는 `--model` 없이 쓸 수 없다. 기본값은 2026-11-02 사용자 결정, 바꾸려면 모델 설정 파일 |
| 워크트리는 `worker-start` 에 합치지 않고 먼저 만든다 | `worker-start --worktree new-…` | 워커를 띄우기 전에 기준선 게이트를 돌려야 한다 — (d) |
| 진행자 워커가 `ask` 로 설계 세션의 답을 기다리는 동안, 정착한 하위 워커의 재사용·보존·해제와 그 ack 를 미룬다 | 정착을 받으면 곧바로 셋 중 하나를 정하고 ack | 답이 정한다 — 수정 라운드면 재사용, 중단이면 보존, 성공이면 해제 — (h). 2026-11-02 결정(Q12) |
| 진행자 워커가 하위 워커를 기다리는 `check --wait` 는 `--timeout-ms 600000` | 가이드 예시 900000 | 빈 대기마다 화면·liveness 를 보는 체크포인트 간격이다 — (e). 설계 세션의 대기는 가이드 기본 그대로 |

## 단계 목록

각 단계에 들어서면 먼저 해당 파일을 Read 한다. 읽기 전에는 그 단계를 판정하지 않는다.

| 단계 | 하는 일 | 먼저 Read 할 파일 |
|---|---|---|
| 설계 (b) | spec 작성, run/task 생성, 진행자 워커 감독 | `references/design.md` (+ `spec-template.md`) |
| 시작 (c) 0~3 | 진행자 워커: preamble 확인, Orca 스킬, doctor, spec 읽기 | `references/start.md` |
| 구현 워커 (d) | worktree·기준선·trust·예열·기동·전달 확인 | `references/implementer.md` |
| 리뷰 워커 (d) | model reviewer·diff-guard·기동 | `references/reviewer.md` |
| 대기 (e) | 대기와 무응답 판정 | `references/wait.md` |
| 게이트 (f) | 독립 재검증, 통과 즉시 커밋 | `references/gate.md` |
| 리뷰 분기 (g) | review-branch, 수정 라운드 | `references/review.md` |
| 에스컬레이션 (h) | 설계 세션에 `ask`, 시도와 라운드 | `references/escalation.md` |
| 종료 (i) | 하위 워커 정리, 경로 A/B, `worker_done` 보고 | `references/finish.md` |

예외 경로는 해당 상황에서만 읽는다.

- 변이 테스트 게이트 → `references/gate-mutation.md`

## (j) 컨텍스트 위생 규범

설계 세션과 진행자 워커가 모두 지킬 것:

1. **`orca ... --json` 출력에서 필요한 필드만 추출해서 읽는다.** orca의 JSON 응답은 크고, 매 턴 재전송되어 비용이 누적된다.
2. **진행자 워커 하나는 태스크 하나만 맡는다.** `worker_done` 뒤 설계 세션이 해제하고, 다음 태스크는 새 진행자 워커가 맡는다. 한 진행자가 여러 태스크를 돌면 컨텍스트가 선형 누적되고, 재전송 비용은 그 누적의 합이라 제곱으로 늘어난다.
3. 설계 세션은 태스크 상태를 `task-list --ready`로 매번 조회한다. 컨텍스트에 들고 있지 않는다. 진행자 워커는 preamble의 Task만 본다.

## (k) 병렬 실행 정책

현재는 **순차 실행**이다. 단 `task-create --deps`로 DAG는 처음부터 정의한다 —
나중에 병렬로 전환할 때 태스크 정의를 고치지 않고 실행 정책만 바꾸면 되게 하기 위해서다.
승격 기준은 **연속 5개 태스크가 에스컬레이션 없이 통과**하는 것이다.
의존 사슬은 3~4단계를 넘기지 않는다(Orca 가이드 권고).

## 왜 세션을 둘로 나누는가

Claude Code는 매 턴 전체 컨텍스트를 재전송하므로 비용은 (컨텍스트 크기 × 턴 수)에 비례한다.
진행 루프는 태스크당 10~20턴인데 판단 함량이 거의 없다(대부분 조건 분기).
반면 설계·명세·중재는 턴 수가 적고 판단 함량이 최대다.
따라서 잦고 긴 구간은 effort 가 낮은 진행자 워커에, 드물고 짧은 구간은 effort 가 높은 설계 세션에 배치한다. 기본은 둘 다 Opus 계열이고 effort 만 다르다(설계 high, 진행 low). 역할별 값은 모델 설정 파일에서 바꾼다.

**진행자 워커를 태스크마다 새로 띄우는 이유**: 진행 루프의 컨텍스트(워커 JSON, 게이트 로그, 리뷰 리포트)는 다음 태스크에 쓸모가 없다. 태스크가 끝날 때 워커를 해제하면 그 컨텍스트가 통째로 사라지고, 설계 세션에는 `worker_done` 요약과 답한 질문만 남는다. 그래서 설계 세션은 Run 끝까지 떠 있어도 태스크 수만큼 비대해지지 않는다.
Orca가 상태(Run/Task/Dispatch)를 소유하므로 진행자 워커를 버려도 잃는 것이 없다. 설계 세션 자신도 컨텍스트가 커지면 새 세션에서 `run-use`로 이어 간다(ADR 0004).

## 이 스킬 자체를 고칠 때

> **이 스킬 자체를 고칠 때**: 소스의 정본은 `scripts` 저장소의 `plugins/relay/` 이고, 설치본은 Claude Code가
> `plugins/cache/hdmun-scripts/relay/<version>/` 에 버전 경로로 두는 관리 복사본이다. 직접 고치지 않는다.
> 소스를 고친 뒤 `plugin.json` 의 `version` 을 올리고 `claude plugin update relay` 를 설정 디렉터리마다 실행한다.
>
> **저장소 쪽 역할 파일**(`.ai/roles/`)은 이 플러그인의 `templates/` 가 역할 파일의 정본이다. 저장소에서 `/relay:init` 으로
> 생성하고, 플러그인을 업데이트한 뒤에는 `/relay:init --check` 로 드리프트를 확인한다(종료코드 1이면 드리프트).
> **역할 파일을 손으로 고치지 않는다** — 공유 규범은 `templates/` 를, 저장소 고유분은 `.ai/relay-roles.json` 을 고친다.
