---
status: accepted
---

# 워커 기동과 orca 명령 문법을 Orca 가이드에 맡긴다

relay 는 Orca 기본 경로(`worker-start --agent`) 대신 터미널 선기동(`terminal create` → `tui-idle` → `worker-start --terminal`), `$null=1; agy`·`codex --yolo` 명령줄, readiness 사다리를 직접 운영해 왔다. Orca 1.4.216~1.4.224 에서 실측한 사고(agy 입력 유실, codex 확인창 한 번으로 Task `failed`, 샌드박스 안의 codex 가 `worker_done` 을 못 보냄) 때문이었다. 그 대가로 references 에 orca 명령 스냅숏이 30개쯤 쌓였고, Orca 가 버전마다 바뀌는 동안 relay 문서가 조용히 어긋날 자리가 늘었다. 이제 Orca 는 **Orca 스킬**(`orchestration`·`orca-cli`)로 버전 맞춤 가이드를 내주고, `worker-start` 가 antigravity·codex 의 `--model`·`--effort` 를 받는다. 그래서 relay 문서는 명령 문법을 적지 않고 Orca 스킬로 가이드를 불러 따르며, 워커는 `worker-start --agent` 로 띄운다. **전환은 에이전트별로 smoke(`worker-start --agent` 경로 3/3)를 통과한 뒤에만 한다.** 통과하지 못한 에이전트는 기존 선기동을 SKILL.md 의 「Orca 기본과 다른 점」에 실패 증거와 함께 남긴다.

## Considered Options

- **명령 문법만 맡기고 기동 방식은 유지**: 스냅숏은 줄지만 relay 가 기동 경로를 운영하는 코드(readiness 사다리, 명령줄 조립)와 문서가 그대로 남는다. 기각.
- **진입에서 Orca 스킬만 부르고 references 는 유지**: 어긋남의 원인(스냅숏)이 그대로다. 기각.
- **측정 없이 바로 전환**: 실측으로 만든 우회를 근거 없이 버리게 된다. 기각.
- **새 에이전트 탭 설정을 "터미널"로 강제하고 화면 검사 유지**: 채팅으로 뜨는 워커를 배제한다. smoke 에서 Orca projection 이 확인창을 잡지 못할 때의 후퇴안으로만 남긴다.

## Consequences

- ADR 0001 의 "스크립트는 orca 명령을 조립하지 않는다"는 그대로다. "명령 조립은 SKILL.md 가 한다"는 "명령 조립은 에이전트가 Orca 가이드를 읽고 한다"로 좁혀진다.
- ADR 0002 의 "agy 명령은 `$null=1; agy [--model …] [--effort …]`" 는 smoke 를 통과한 에이전트에 한해 대체된다. model·effort 는 `worker-start` 인자로 주고, 실제 값은 `launch.effective` 에서 읽는다.
- 워커 관찰은 orchestration 동사(`worker-list` projection, `worker-read`)만 쓴다. 워커가 터미널이 아니라 채팅으로 뜰 수 있기 때문이다.
- `trust`(agy trust 프롬프트는 기동 경로와 무관)와 `warmup`(Task 도중 자동 업데이트)은 남는다. 워크트리 생성도 `worker-start` 에 합치지 않는다 — 기준선 게이트와 trust 등록이 워커 기동 전에 워크트리 경로를 필요로 한다.
- 코디네이터와 워커 모두 `~/.agents/skills` 의 Orca 스킬로 가이드를 읽는다. `doctor` 가 그 설치를 검사한다.
