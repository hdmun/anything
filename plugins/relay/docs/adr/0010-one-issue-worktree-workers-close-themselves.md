---
status: accepted
---

# 이슈 워크트리 하나에서 워커를 띄우고, 정리는 Orca 의 자동 닫힘을 따르며, 끝난 태스크는 트레일러로 안다

ADR 0007 로 구현 이슈 하나가 브랜치 하나가 되었고, Orca 1.4.247 가이드는 워커가 `worker_done` 뒤 알아서 닫히고(닫힌 워커에 `send` 하면 후속 Task 로 다시 열린다) 코디네이터가 워크스페이스를 직접 만들지 말라고 한다. 그래서 **`relay:handoff` 가 `worktree create --name I-<n>-<슬러그> --no-parent --base-branch main --agent claude` 로 이슈 워크트리와 진행자 세션을 한 번에 띄우고, 진행자는 구현자·리뷰어를 모두 `--worktree current` 로 띄운다.** 재개 때 같은 이름의 워크트리가 있으면 handoff 는 그 워크트리에 `agent launch` 한다. 하위 워커 정리는 출구 세 줄만 남는다: 성공은 할 일 없음, 수정 라운드는 구현 dispatch 에 `send`(리뷰어는 라운드마다 새 워커), 멈춤 보고는 둘 다 `worker-keep-open`(증거). `trust remove` 는 PR 을 열 때 한 번 한다.

재개 때 끝난 태스크는 **트레일러 `Relay-Done: I-<n>`** 로 안다. 리뷰 `pass` 면 리뷰 리포트 커밋에, 판정 서브에이전트가 성공으로 처리하면 그 판정 기록 커밋에 단다. 결정기 `relay_cli resume` 이 DAG 순서의 태스크 목록과 브랜치를 보고 다음 태스크를 돌려준다.

## Considered Options

- **태스크마다 워크트리(옛 구조)**: 태스크가 같은 브랜치에 쌓인다는 ADR 0007 과 맞지 않는다. 기각.
- **진행자가 워크트리를 먼저 만든다(옛 「Orca 기본과 다른 점」 행)**: 근거였던 기준선 게이트는 진행자가 이슈 워크트리 안에서 워커를 띄우기 전에 돌리면 된다. Orca 가이드가 금지한다. 기각.
- **`release`·`retain`·`--terminal` 재사용으로 정리를 relay 가 정한다**: 1.4.247 에서는 자동 닫힘과 `send` 재개방이 같은 일을 한다. 기각.
- **「마지막 리뷰가 `pass`」로 끝난 태스크를 안다(ADR 0008 원문)**: `지적을 기각한다`·성공 처리로 끝난 태스크를 다시 돌게 된다. 기각.

## Consequences

- 「Orca 기본과 다른 점」에서 워크트리 선생성·`ask` 대기 중 정리 미루기·`check --wait 600000` 행이 빠지고, 게이트 상시 재검증·리뷰어 라운드마다 새 워커 행이 더해진다. `--base-branch main` 명시는 handoff 쪽 표에 둔다(`defaultBaseRef` 가 `null` 인 저장소).
- `review_round_limit`(`MAX_REVIEW_ROUNDS`)은 정상 흐름에서 도달하지 않아 지운다. 한도는 `total_round_limit`(5)만 남고 그 결과는 멈춤 보고다.
- 트레일러가 빠진 성공 태스크는 재개 때 다시 돈다. commit-guard 와 같은 이유로 트레일러는 진행자가 커밋할 때 붙인다.
