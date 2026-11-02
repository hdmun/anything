---
name: relay
description: Orca orchestration 위에서 설계자(Opus)·진행자(Sonnet)·구현자(agy)·리뷰어(codex) 4역할 파이프라인을 굴릴 때 사용한다. spec 작성부터 워커 dispatch, 게이트 재검증, 리뷰 심각도 분기, PR 생성까지를 다룬다. "relay", relay Run/Task 진행, T-NNN spec 설계를 요청할 때 쓴다. 작업을 다른 워크트리나 에이전트에 통째로 넘기는 단순 위임(handoff — 감독·리뷰 없이 맡기기)에는 쓰지 않는다.
---

# relay

`relay`는 3개 AI 코딩 에이전트를 Orca orchestration 위에서 연결하는 파이프라인의 코디네이터 스킬이다.

## 진입 약속과 세션 판정

**첫 요청에 "relay"를 명시해 이 스킬을 부른다.** 설계 세션도 진행 세션도 마찬가지다. 예: "relay로 T-NNN 설계해줘", "relay Run `<id>` 진행해줘".

| 구분 | 설계 세션 | 진행 세션 |
|---|---|---|
| 실행 주체 | Claude Code Opus / high | Claude Code Sonnet / medium |
| 하는 일 | spec 작성, run/task 생성, 심각도 판단(SPEC_VIOLATION 등) | 워커 부트스트랩, dispatch, 대기, 게이트 재검증, 리뷰 분기, PR 생성 |
| 끝나는 지점 | `task-create` 완료 후, Run ID를 사용자에게 알리고 세션 종료 | 태스크 하나가 성공 종료(i)되거나 사람 에스컬레이션이 발생한 직후 세션 폐기 |
| Orca에서의 위치 | 코디네이터 자신 (워커 아님) | Run에 재바인딩되는 코디네이터. 구현/리뷰는 워커로 dispatch |
| 판단 함량 | 최대 (새 개념, 되돌리기 어려운 결정) | 최소 (대부분 조건 분기) |

읽는 사람이 "지금 나는 어느 세션인가"를 판단하는 기준: **run-create/task-create를 아직 안 했으면 설계 세션, run-use로 기존 Run에 들어왔으면 진행 세션.**

- 설계 세션이면 먼저 `references/design.md`를 Read 한다.
- 진행 세션이면 먼저 `references/start.md`를 Read 한다.

## 역할과 모델

| 역할 | 실행 주체 | 모델 계열 / effort | Orca에서의 위치 |
|---|---|---|---|
| 설계자 | Claude Code | Opus (`/model opus`) / high | 코디네이터 자신 (워커 아님) |
| 진행자 | Claude Code | Sonnet (`/model sonnet`) / medium | Run에 재바인딩, 태스크당 세션 폐기 |
| 구현자 | agy (Antigravity CLI) | agy 기본 모델 — (d) 참조 | supervised worker |
| 리뷰어 | codex | 모델 설정 파일의 `reviewer.model` (필수) / high | supervised worker |

**이 스킬은 모델 버전을 적지 않는다.** 위 표는 **기본값**(모델 계열)이고, 사용자가 정하는 값은 설정 파일에 있다. 실제로 쓰인 버전은 커밋 트레일러(`Implemented-by:`, `Reviewed-by:`)에 사후로 남긴다.

모델·effort 설정 파일의 형식, 우선순위, 역할별 규칙은 `references/models.md`에 있다. 그 파일을 Read 한 뒤 `relay_cli.py models`에 묻는다.

## 파이프라인 흐름

```
[설계 Opus·high]  /grill-with-docs  (발동 기준은 (b) 참고)
                    ├─ CONTEXT.md 갱신
                    └─ ADR 추가 (해당 시)
                  .ai/specs/T-NNN.md 작성
                  run-create / task-create --deps  → 세션 종료
                          ↓
[진행 Sonnet·med] run-use → 워커 부트스트랩 → worker-start
                          ↓
[구현 agy]        구현 + 자체 게이트 루프
                          ↓
[진행]            게이트 독립 재검증
                          ↓
[리뷰 codex·high] .ai/reviews/T-NNN.rN.json 작성
                          ↓
[진행]            스키마 검증 → 심각도 분기 → PR 생성 → 워커 정리 → 세션 폐기
```

## 불변식

모든 경로에 적용된다. 아래 단계 파일을 읽은 뒤에도 이 규칙이 우선한다.

- 구현자는 `--command '$null=1; agy'` 그대로 띄운다 (단독 `agy` 금지).
- 리뷰어는 `codex --yolo -m <model> -c model_reasoning_effort=<effort>`로 띄운다 (`--yolo` 유지).
- 구현·리뷰 워커 모두 `terminal create` → `tui-idle`(Task 밖) → `worker-start --terminal` 순서로 띄운다.
- 게이트는 종료코드로 판정한다. 통과하면 즉시 구현 커밋을 만든다.
- `<base>`는 spec과 리뷰 Task에 명시한다.
- 자동 머지 금지. 프롬프트 자동 응답 금지.
- `relay_cli` 결정기는 stdout JSON 한 줄의 `action`대로 행동한다. 검사기는 종료코드 0 통과 / 1 실패 / 2 입력 오류다.
- Orca 가이드(`orca skills get orchestration`)와 충돌하면 relay 문서를 고친다.

## 단계 목록

각 단계에 들어서면 먼저 해당 파일을 Read 한다. 읽기 전에는 그 단계를 판정하지 않는다.

| 단계 | 하는 일 | 먼저 Read 할 파일 |
|---|---|---|
| 설계 (b) | spec 작성, run/task 생성 | `references/design.md` (+ `spec-template.md`) |
| 시작 (c) 0~2 | doctor·model 점검, run-use, task-list | `references/start.md` |
| 구현 워커 (d) | worktree·기준선·trust·예열·기동·전달 확인 | `references/implementer.md` |
| 리뷰 워커 (d) | model reviewer·diff-guard·기동 | `references/reviewer.md` |
| 대기 (e) | 대기와 무응답 판정 | `references/wait.md` |
| 게이트 (f) | 독립 재검증, 통과 즉시 커밋 | `references/gate.md` |
| 리뷰 분기 (g) | review-branch, 수정 라운드 | `references/review.md` |
| 에스컬레이션 (h) | 사람 호출, 시도와 라운드 | `references/escalation.md` |
| 종료 (i) | 워커 정리, 경로 A/B | `references/finish.md` |

예외 경로는 해당 상황에서만 읽는다.

- `tui-idle` timeout, `blocked_prompt` → `references/readiness.md`
- 변이 테스트 게이트 → `references/gate-mutation.md`

## (j) 컨텍스트 위생 규범

진행 세션이 반드시 지킬 것:

1. **`orca ... --json` 출력을 원본 그대로 받지 말 것.** 항상 필요한 필드만 추출해서 읽는다. orca의 JSON 응답은 크고, 매 턴 재전송되어 비용이 누적된다.
2. **태스크 하나가 끝나면 세션을 폐기한다.** 여러 태스크를 한 세션에서 돌리면 컨텍스트가 선형 누적되고, 재전송 비용은 그 누적의 합이라 제곱으로 늘어난다.
3. 태스크 상태는 `task-list --ready`로 매번 조회한다. 컨텍스트에 들고 있지 않는다.

## (k) 병렬 실행 정책

현재는 **순차 실행**이다. 단 `task-create --deps`로 DAG는 처음부터 정의한다 —
나중에 병렬로 전환할 때 태스크 정의를 고치지 않고 실행 정책만 바꾸면 되게 하기 위해서다.
승격 기준은 **연속 5개 태스크가 에스컬레이션 없이 통과**하는 것이다.
의존 사슬은 3~4단계를 넘기지 않는다(Orca 가이드 권고).

## 왜 세션을 둘로 나누는가

Claude Code는 매 턴 전체 컨텍스트를 재전송하므로 비용은 (컨텍스트 크기 × 턴 수)에 비례한다.
코디네이터 루프는 태스크당 10~20턴인데 판단 함량이 거의 없다(대부분 조건 분기).
반면 설계·명세·중재는 턴 수가 적고 판단 함량이 최대다.
따라서 잦고 긴 구간은 Sonnet에, 드물고 짧은 구간은 Opus에 배치한다.
Orca가 상태(Run/Task/Dispatch)를 소유하므로 세션을 버려도 잃는 것이 없다 — `run-use`로 재바인딩한다.

## 이 스킬 자체를 고칠 때

> **이 스킬 자체를 고칠 때**: 정본은 `scripts` 저장소의 `plugins/relay/` 이고, 설치본은 Claude Code가
> `plugins/cache/hdmun-scripts/relay/<version>/` 에 버전 경로로 두는 관리 복사본이다. 직접 고치지 않는다.
> 소스를 고친 뒤 `plugin.json` 의 `version` 을 올리고 `claude plugin update relay` 를 설정 디렉터리마다 실행한다.
>
> **저장소 쪽 역할 파일**(`.ai/roles/`)은 이 플러그인의 `templates/` 가 정본이다. 저장소에서 `/relay:init` 으로
> 생성하고, 플러그인을 업데이트한 뒤에는 `/relay:init --check` 로 드리프트를 확인한다(종료코드 1이면 드리프트).
> **역할 파일을 손으로 고치지 않는다** — 공유 규범은 `templates/` 를, 저장소 고유분은 `.ai/relay-roles.json` 을 고친다.
