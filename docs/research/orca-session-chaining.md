# Orca 에서 세션이 끝난 뒤 다음 세션을 띄우는 방법

- 이슈: hdmun/anything#56 (지도 #51 「relay 무인 진행: 계획된 구현 이슈를 머지까지 사람 없이」)
- 조사일: 2026-11-09
- 기준 버전: `orca --version` = `1.4.253` (설치본 `orca.exe`)
- 범위: Orca 가 무엇을 주는지만 모은다. 어떤 수단으로 다음 진행자 세션을 띄울지는 정하지 않는다(뒤 티켓의 몫).
- 방법: 읽기 전용. Run·Task·워크트리·터미널·자동화·세션을 만들지 않았고, 터미널에 입력하지 않았다. 아래 출처만 읽었다.

## 출처

| 약칭 | 내용 |
| --- | --- |
| [orch] | `orca skills get orchestration` 출력. 숫자는 그 출력의 줄 번호 |
| [orch/<이름>] | `orca skills get orchestration --reference references/<이름>.md` |
| [cli] | `orca skills get orca-cli` 출력. 숫자는 줄 번호 |
| [cli/<이름>] | `orca skills get orca-cli --reference references/<이름>.md` |
| [plugin] | `orca skills get orca-plugin-authoring` 출력 |
| [plugin/<이름>] | `orca skills get orca-plugin-authoring --reference references/<이름>.md` |
| [help: <명령>] | `orca <명령> --help` 출력 (`orca agent-context --json` 의 notes 와 같다) |
| [plan] | `plugins/relay/docs/plan.md` — 1.4.245 에서 잰 기록. 현재 버전의 근거가 아니라 과거 실측이다 |
| [ADR 000N] | `plugins/relay/docs/adr/` |

**사실**은 위 출처에 적힌 것이다. 출처에 없으면 **미확인**이라고 쓴다.

## 요약

| 수단 | 할 수 있는 일 | 제약 | 근거 |
| --- | --- | --- | --- |
| automations | 정해진 시각에 provider(예: `claude`)를 프롬프트와 함께 띄운다. 실행마다 새 워크트리(`--repo`) 또는 기존 워크트리(`--workspace`) | 트리거는 **일정뿐**(hourly·daily·weekdays·weekly·5필드 cron·RRULE). 세션 종료 같은 이벤트 트리거는 문서에 없다. `--precheck` 명령이 0 이 아니면 그 회차를 건너뛴다. `automations run <id>` 는 즉시 실행(precheck 건너뜀) | [cli/automations] 3·17·19·21·23, [help: automations create] |
| 세션 안에서 `worktree create --agent` / `agent launch` | 세션이 다음 세션을 새 워크트리(또는 기존 워크트리)에 띄우고 끝난다 — 가이드의 「full handoff」 | 받은 세션이 끝나기를 기다리지 않는다. 띄운 세션은 Task 로 추적하지 않는다(`task-create` 금지). 부모 lineage 는 `--no-parent` 가 없으면 부르는 쪽으로 잡힌다. 연쇄 횟수·깊이 제한은 문서에 없다(미확인) | [cli] 27·29·31·35-39·51-55·140-146 |
| 상위 코디네이터가 진행자 세션을 워커로 | `worker-start --agent claude --worktree new-top-level …` 로 진행자를 워커로 띄우고 `worker_done` 으로 깨어난다. Task DAG(`--deps`)로 순서를 표현한다 | 진행자가 다시 워커를 띄우면 중첩 dispatch 다. 1.4.245 실측: 기본 최대 깊이 1, `nested_worker_depth_exceeded`. 1.4.253 가이드·help 에 깊이 한도가 없다(현재 기본값 미확인). 새 워크트리 워커는 끝나도 열린 채 남는다 | [orch] 33-35·38-44, [orch/coordinator-loop] 15, [help: orchestration worker-start], [plan] 167 |
| 깨우기 (orchestration) | 워커의 `worker_done`·`escalation`·`question` 이 그 Run 의 코디네이터를 깨운다. 끝났거나 닫힌 워커에 `send` 하면 후속 Task 로 다시 열린다 | Run 자체에는 「끝남」 상태·이벤트가 없다. Run 밖 최상위 세션이 끝나도 아무도 알림을 받지 않는다(문서에 없음). 폴링 금지 | [orch] 48-52·57-62·64-77, [help: orchestration run-create] |
| 깨우기 (플러그인 워커) | `agent.status.changed`(`state: done` 등)·`workspace.created/removed` 이벤트를 받아 `agent.launch`·`terminal.create` 를 부를 수 있다 | `trusted-worker` 플러그인이어야 하고 사람이 승인해야 한다. `agent.launch` 인자는 `workspaceId`·`agent`·`prompt` 뿐(model·effort 없음). 호스트 API 에 워크트리 생성 호출은 없다 | [plugin/events] 9-14, [plugin/host-api] 9·118-123·150-162, [cli/plugins] 157-176 |
| 세션이 스스로 끝나기 | 워커: `worker_done` 을 보내면 Task 가 정산되고 워커는 스스로 닫힌다. 그 밖의 세션: 턴을 끝낸다 | 워커가 아닌 세션이 자기 프로세스·터미널을 닫는 명령은 가이드에 없다(미확인). chat 탭에는 터미널 핸들이 없다 | [orch] 79-85, [help: orchestration worker-start], [cli] 27·242-246 |

결정에 가장 직접 닿는 사실:

1. **Orca 에는 「세션이 끝나면 다음 세션을 띄운다」는 내장 트리거가 없다.** automations 는 일정 트리거뿐이고, Run 에는 완료 상태·이벤트가 없다. 세션 종료를 알아채는 공식 신호는 (a) 워커의 `worker_done`(코디네이터를 깨움)과 (b) 플러그인 워커의 `agent.status.changed` 둘이다.
2. **세션이 직접 다음 세션을 띄우는 것은 가이드가 정식으로 다루는 경로다**(full handoff). 다만 띄운 뒤 결과를 돌려받지 않는 것이 전제다.
3. **상위 코디네이터가 진행자를 워커로 두면 깊이가 2 가 된다.** 1.4.245 에서는 기본값 1 이라 거부됐고 설정을 2 로 올려야 했다(ADR 0004, [plan]). 1.4.253 의 기본값은 이번 조사로 확인하지 못했다.

---

## 1. automations

### 사실

- 정의: "An automation is a scheduled Orca prompt run by a chosen provider against either a repo-created worktree or an existing workspace." — [cli/automations] 3
- **트리거**: `hourly`, `daily`, `weekdays`, `weekly`, 5필드 cron, RRULE. `--time <HH:MM>`(daily·weekdays·weekly), `--day <0-6>`(weekly) — [cli/automations] 17. help 도 같다: "Trigger accepts hourly, daily, weekdays, weekly, a 5-field cron expression, or an RRULE string." — [help: automations create]
  - 이벤트(세션 종료, Run 종료, PR 머지 등) 트리거는 가이드·help 어디에도 없다.
- **precheck**: `--precheck <command>` 는 예약 실행 전에만 돈다. 종료코드 0 이면 진행, 그 밖(오류·시간 초과 포함)이면 그 회차를 건너뛰고 `skipped_precheck` 로 기록한다. 기본 시간 한도 60초(`--precheck-timeout`) — [cli/automations] 19
- **즉시 실행**: Orca 의 Run now 와 `orca automations run <id>` 는 precheck 를 건너뛴다 — [cli/automations] 21. "A queued or dispatching run has been accepted but may not have a workspace or terminal yet." — [help: automations run]
  - 즉, 세션이 CLI 로 `automations run <id>` 를 불러 자동화를 지금 돌릴 수 있다(help 의 사용법 기준. 이번에 실행해 보지는 않았다).
- **대상**: `--repo <selector>` 는 실행마다 새 워크트리, `--workspace <selector>`(또는 `--workspace-mode existing`)는 기존 워크트리. 둘은 함께 못 쓴다. `--reuse-session` 은 기존 워크트리 자동화에서만, 이전 터미널이 없으면 새 세션 — [cli/automations] 23
  - 대상 없이 Orca 워크트리 안에서 만들면 그 워크트리에서 돈다(`--workspace-mode new-per-run` 이 아니면) — [help: automations create]
  - `--base-branch <ref>` 를 받는다 — [help: automations create]
- **모델·effort**: `--extra-agent-args="--model … --effort …"` 로 새 실행마다 붙인다. claude 는 `--add-dir` 도. `--reuse-session` 과 함께 못 쓴다 — [cli/automations] 29
- 그 밖의 플래그: `--enabled`/`--disabled`, `--timezone`, `--missed-run-grace-minutes <n>`(놓친 실행 유예) — [help: automations create]
- 이력: `automations runs --id <id>` — [cli/automations] 13, [help: automations runs]
- 자동화가 띄우는 것은 에이전트 CLI 다: 플러그인 훅 `agent.launch.before` 는 "from any launcher (new tab, workspace create, CLI, automation, orchestration)" 를 잡는다 — [plugin/host-api] 139

### 미확인

- 최소 주기(예: 1분 cron 이 허용되는지), 이전 실행이 아직 도는 중일 때 다음 회차가 겹치는지.
- Orca 앱이 꺼져 있을 때 예약 실행이 도는지. `--missed-run-grace-minutes` 의 정확한 의미.
- 자동화가 띄운 세션이 Run 을 만들고 워커를 띄우는 코디네이터가 될 수 있는지(금지 문구는 없다).
- `--name` 이 실행마다 생기는 워크트리의 이름에 쓰이는지(help 는 "Name for the new worktree or automation" 으로 겸용).

## 2. 세션 안에서 다음 세션을 띄우기 (`worktree create --agent` / `agent launch`)

### 사실

- **가이드가 정식으로 다루는 경로다.** "A full handoff transfers ownership to another agent or worktree, then the original agent stops." — [cli] 27
  - 끝의 정의: "A handoff is done when the new worktree id and agent handle have been reported and the prompt was delivered: the launch's `prompt.outcome` is `journaled` or `handed-to-terminal` … Do not wait for the receiving agent to finish." — [cli] 29
  - full handoff 에는 `task-create`, `dispatch --inject`, `check --wait` 를 쓰지 않는다. `task-create` 는 코디네이터 소유 추적 상태를 남기기 때문이다 — [cli] 31
  - orchestration 가이드도 같은 경로를 준다: 돌려받을 것이 없으면 워커를 띄우지 말고 `worktree create --name <name> --no-parent --agent <agent> --prompt "<brief>" --json` 후 턴을 끝낸다 — [orch] 41-44
- **명령**:
  - 새 체크아웃: `worktree create --name <task-name> --no-parent --agent <id> --prompt "<brief>" --json`, `--model`/`--effort` 추가 가능 — [cli] 35-47, [help: worktree create]
  - 기존 워크트리: `agent launch --agent <id> --worktree id:<repoId>::<worktreePath> --prompt "<brief>" --json`. `--worktree` 를 빼면 현재 디렉터리의 워크스페이스 — [cli] 51-55, [help: agent launch]
  - 영수증: `result.launch.outcome.kind`(`structured` = chat, 또는 `terminal`), `outcome.handle`, `receipt.detail`, `prompt.outcome` — [cli] 49
- **제약**:
  - **lineage**: Orca 워크트리 안에서 만들면 부르는 쪽을 부모로 추론한다. 독립 작업은 `--no-parent`. `--no-parent` 는 lineage 만 정하고 Git base 는 정하지 않는다 — [cli] 138-146, [help: worktree create]
  - **선택자 모호**: 여러 Orca 워크스페이스가 같은 체크아웃을 공유하고 호출자 신원으로 고를 수 없으면, 암묵 생성이 거부되고 `--parent-worktree <정확한 선택자>` 나 `--no-parent` 를 요구한다 — [cli] 77
  - **chat/terminal**: 사용자의 Chat | CLI 설정이 정한다. `--surface chat|terminal` 로 그 기동만 바꾼다 — [cli] 65. chat 탭에는 터미널 핸들이 없다 — [cli] 246
  - **잃어버린 응답**: `--retry-launch <operationId>` 로 같은 명령을 같은 디렉터리·호스트에서 다시 낸다. 새 기동으로 재시도하지 않는다. 프롬프트를 안전하게 나를 수 없는 호스트는 기동 전에 거부된다 — [cli] 67
  - `--agent` 만 주면 백그라운드에 뜬다(`--activate` 가 보여 준다) — [cli] 162
  - `--effort` 는 `--model` 이 있어야 한다 — [help: agent launch]
- relay 의 현재 handoff(설계 세션 → 진행자 세션)가 바로 이 경로다: `worktree create --name I-<n>-<슬러그> --no-parent --base-branch main --agent claude --model … --effort …`, 재개면 `agent launch` — `plugins/relay/skills/handoff/SKILL.md` 3절
- ADR 0005 는 「연쇄 핸드오프(태스크마다 진행자가 다음 진행자를 띄움)」를 기각했다. 근거: Run 승계(`run-use`) 미검증, 핸드오프가 감독 밖에서 반복됨. 재검토 조건은 진행자 컨텍스트 누적이 측정으로 문제가 될 때 — [ADR 0005]

### 미확인

- handoff 를 몇 번 이어서 할 수 있는지(연쇄 횟수·깊이 제한). 가이드·help 에 언급이 없다. 중첩 깊이 한도(3절)는 「sub-worker dispatch」에 대한 것이라 `worktree create` 에도 걸리는지는 문서로 알 수 없다.
- 이전 세션이 끝나기 전에 다음 세션이 뜨는 것(겹침)에 대한 Orca 쪽 제한.

## 3. 오래 사는 상위 코디네이터가 진행자 세션을 워커로 감독하기

### 사실

- **워커로 띄우기**: `worker-start (--task <id> | --spec <text>) --agent <agent> --worktree <current|selector|new-child|new-top-level>`. 새 워크트리는 `--worktree new-top-level --repo id:<repoId> --name <short-name>` — [orch] 30·38-40, [help: orchestration worker-start]
  - Run 이 묶여 있지 않은 코디네이터가 `--spec` 으로 띄우면 Run 이 새로 생겨 묶인다 — [help: orchestration worker-start]
  - "a worker started in a new worktree (new-child or new-top-level) is kept open, so release it when no one will use its chat." — [help: orchestration worker-start]
- **순서**: Task 에 `--deps` 를 주고, 깨어날 때마다 `task-list --ready` 가 보여 주는 Task 를 시작한다 — [orch/coordinator-loop] 5-15
- **여러 Run**: 나중의 `run-create` 는 앞 Run 을 남긴다. 앞 Run 의 메일도 깨운다. `--run` 없는 명령은 최신 Run 을 쓴다 — [orch/coordinator-loop] 17-21
- **이미 떠 있는 세션을 워커로 들이기**: "To give a Task to a terminal or chat Orca did not start: `worker-start --task <task_id> --terminal <handle> --worktree <its_workspace>`" — [orch/low-level-topology] 9-13
- **중첩 코디네이터의 흔적(1.4.253 help)**:
  - "Nested coordinators receive group mail in their child Run mailbox" — [help: orchestration send]
  - "A worker cannot bind its own or ancestor Run" — [help: orchestration run-use]
  - "… including mail it read before it bound a helper Run." — [help: orchestration check]
  - 즉 워커가 자기 하위(helper) Run 을 묶는 것을 Orca 가 상정한다.
- **중첩 깊이 한도 — 1.4.245 실측만 있다**: 진행자 워커가 agy 하위 워커를 띄우자 `nested_worker_depth_exceeded`: "Sub-worker dispatch is not permitted at depth 2 (max 1)". 설정 `nestedWorkerMaxDepth` 기본값 1, Settings → Orchestration → "Nested worker depth"(한국어 UI: 설정 → 에이전트 오케스트레이션 → "하위 에이전트 최대 생성 단계"). 2 로 올리자 동작했고, 하위 워커의 `worker_done` 은 상위가 아니라 진행자 inbox 로 갔다 — [plan] 167, [ADR 0004]
- **묻기**: 워커의 `ask` 는 코디네이터에게 가고 즉시 돌아온다(턴을 끝내면 답이 메일로 깨운다). `--wait`/`--resume` 은 막고 기다리며 한 번에 최대 30분 — [help: orchestration ask]
- **기동 실패 한도**: 한 `--retry-of` 사슬에서 기동 3회 실패면 circuit-break, Task 실패 — [orch/recovery-and-cleanup]
- 다른 세션 찾기: `reference find <URL 또는 이슈 키>` 는 워크스페이스의 에이전트와 `liveness`(`live`·`unverifiable`·`exited`), 우편함(`dispatch:<id>` = 감독되는 워커, `run:<id>` = 코디네이터)을 돌려준다 — [cli] 180-182

### 미확인

- **1.4.253 의 중첩 깊이 기본값과 설정 이름.** 현재 가이드·help·`agent-context` 에 `depth` 관련 항목이 없다. 1.4.245 이후 바뀌었는지 모른다.
- 상위가 `--terminal` 로 들인(Orca 가 시작하지 않은) 세션이 하위 워커를 띄울 때 깊이가 어떻게 세어지는지.
- 진행자를 워커로 띄우면 워커 preamble(Task·Dispatch ID)이 붙는다. relay 진행자 스킬은 지금 preamble 이 없는 최상위 코디네이터를 전제로 한다(ADR 0005 Consequences). 이 차이가 동작에 주는 영향은 이번 범위 밖이다.

## 4. Run·워커가 끝났을 때 다른 세션을 깨우는 수단

### 사실 — orchestration 메일

- 코디네이터: 워커를 띄운 뒤 턴을 끝내면 Orca 가 깨운다. "Report back" 도 턴을 끝내라는 뜻이다 — [orch] 33-35
- 깨우는 것: 메일(`worker_done`, `escalation` + `stopReason` = 워커가 `worker_done` 없이 멈춤, `question`) — [orch] 64-77
- 워커: `send --to dispatch:<id>` 는 어느 상태든 닿는다. 일하는 워커는 현재 턴이 끝날 때 받고, 끝났거나 닫힌 워커는 후속 Task 로 받아 `worker_done` 으로 보고한다 — [orch] 48-52. `send` 는 닫힌 워커를 다시 연다 — [orch] 81
- Run 밖 발신자: "a sender in no Run must use run:<id> or dispatch:<id>" — [help: orchestration send]. `@worktree:<id>` 는 그 워크스페이스의 코디네이터에게도 닿는다 — [orch/messaging-and-gates] 5-7
- 메일 type: `status, dispatch, worker_done, merge_ready, escalation, handoff, decision_gate, question, heartbeat` — [help: orchestration send]
- **Run 에는 완료가 없다**: "A Run is a namespace and home inbox. It never schedules or places workers." — [help: orchestration run-create]. Run 동사는 `run-create`·`run-use`·`run-current`·`run-list`·`run-show` 뿐이고 닫기·완료 동사가 없다 — [help] 최상위 목록
- **금지**: 폴링·감시 스크립트. 스크립트의 일반 `check` 가 메일을 가져가 Orca 가 깨울 근거가 없어진다 — [orch] 57-62. 감시만 하는 스크립트는 `--peek`(`--peek --wait` 포함)을 쓰고 `--ack` 하지 않는다 — [help: orchestration check]
- 침묵·시간 초과·`unverifiable` 은 종료의 증거가 아니다 — [orch] 99-102

### 사실 — 막고 기다리는 명령

- `orchestration check --wait --timeout-ms <n>`: 메일이 오거나 시간이 다할 때까지 막는다 — [help: orchestration check]
- `terminal wait --terminal <handle> --for exit|tui-idle --timeout-ms <ms>` — [help: terminal wait], [cli] 262
- `worktree ps --agent-wait` — 에이전트 행마다 대기 판정 — [help: worktree ps]

### 사실 — 플러그인 워커 이벤트

- 워커 이벤트(`contributes.events` + `orca.events.on`, `trusted-worker`) — [plugin/events] 5-16:
  - `agent.status.changed`(`agent:read`, 1.4.160+): "An agent in a terminal pane changed status". payload 에 `state: "working" | "blocked" | "waiting" | "done"`, `mainAgent.outcome?: "success" | "failure" | "cancellation" | "superseded" | "interruption" | "unconfirmed"`, `workspaceId`, `terminalId`
  - `workspace.created`·`workspace.removed`(`workspace:read`, 1.4.245+), `workspace.changed`(1.4.246+)
- 쉬는 워커는 멈췄다가 다음 명령·이벤트·패널 요청에 다시 뜬다 — [plugin/recipes] 22-25
- 워커가 부를 수 있는 호스트 호출 — [plugin/host-api] 9·114-123:
  - `agent.launch({ workspaceId, agent, prompt? })`(`agent:launch`): "Starts an agent's CLI in a new terminal of a workspace, in the background … a `prompt` is sent once the agent is ready." 인자에 model·effort 가 없다
  - `terminal.create({ workspaceId, title?, command? })`(`terminal:send`), `terminal.read`(`terminal:read`), `workspace.list`(`workspace:read`)
  - 호출 목록에 워크트리(워크스페이스) 생성은 없다
- 훅(`contributes.hooks`, 1.4.248+): `workspace.create.before/.after`, `agent.launch.before`(명령줄·env 변경 또는 거부), `agent.prompt.before`, `agent.tool.before/.after`, `terminal.send`, `editor.save.before`. 훅마다 2초 — [plugin/host-api] 129-148
- 승인: 코드를 돌리는 플러그인은 `approval_required`(종료코드 3)로 멈추고, 사람이 `--approve <fingerprint>` 로 승인해야 한다. 플러그인 시스템이 꺼져 있으면 `plugin_system_disabled` — [cli/plugins] 99-102·157-176, [plugin] 89-97

### 미확인

- Run 밖 세션이 보낸 `send --to run:<id>` 메일이 그 Run 의 코디네이터를 깨우는지(문법상 허용되지만 실측 없음).
- 워커가 아닌 최상위 세션(지금의 relay 진행자)이 끝났을 때 Orca 가 다른 세션에 알리는 수단. 문서에 없다.
- `agent.status.changed` 의 `done` 이 턴 종료인지 프로세스 종료인지. chat 표면 에이전트도 이 이벤트를 내는지(문서는 "in a terminal pane").
- 이 머신에서 플러그인 시스템이 켜져 있는지(조회하지 않았다).

## 5. 세션이 스스로 끝나는 방법

### 사실

- **워커**: `send --type worker_done --outcome succeeded|failed` 가 Task 를 정산한다. `worker_done` 은 dispatch 된 pane 에서만 Task 를 완료한다 — [help: orchestration send], [orch] 73
  - "Finished workers close on their own unless `worker-list` gives one a `next`" — [orch] 79. `--keep-open` 이나 새 워크트리 워커는 열린 채 남는다 — [help: orchestration worker-start]
  - 자동 해제는 `resource.autoReleaseAt` 에 일어나고, `worker-keep-open` 이나 `--terminal` 재사용이 취소한다 — [help: orchestration worker-list], [help: orchestration worker-keep-open]
- **워커가 아닌 세션**(full handoff 의 원래 세션, 최상위 코디네이터): 가이드는 "then the original agent stops"(= 턴을 끝낸다)라고만 쓴다 — [cli] 27. 자기 프로세스를 끝내는 Orca 동사는 가이드에 없다.
  - 관련 명령(남이 닫는 용도로 문서화됨):
    - `terminal close --terminal <handle>` — 터미널 하나. `--worktree <selector> --all` — 그 워크스페이스의 모든 터미널 프로세스를 멈추고 탭·레이아웃·resume 기록을 지운다 — [cli] 242, [help: terminal close]
    - 나중에 이어 쓸 세션이면 close 가 아니라 workspace Sleep — [cli] 244. Sleep 의 CLI 동사는 help 에 없다
    - chat 탭에는 터미널 핸들이 없다 — [cli] 246
  - 사람에게 알리는 표지: `worktree set --worktree active --workspace-status <id>`(기본 `todo`·`in-progress`·`in-review`·`completed`), `--unread` — [cli] 199, [help: worktree set]
- relay 진행자의 현재 「끝난다」는 사람에게 한 줄 보고하고 턴을 끝내는 것이다 — `plugins/relay/skills/relay/references/finish.md` 81행

### 미확인

- 세션이 자기 터미널을 `terminal close` 로 닫아도 되는지(가이드가 다루지 않는다). 세션이 자기 터미널 핸들을 얻는 방법.
- chat 표면 세션이 스스로 닫히는 방법.
- 에이전트 CLI 자체의 종료(예: Claude Code 를 빠져나가기)는 Orca 가이드 범위 밖이라 보지 않았다.

## 미확인 모음

1. 1.4.253 의 워커 중첩 깊이 기본값·설정 이름 (1.4.245 실측: 기본 1, `nestedWorkerMaxDepth`)
2. `worktree create --agent` 연쇄 handoff 의 횟수·깊이 제한
3. automations: 최소 주기, 회차 겹침, 앱이 꺼져 있을 때의 동작, 자동화 세션이 코디네이터가 될 수 있는지
4. Run 밖 세션의 `send --to run:<id>` 가 코디네이터를 깨우는지
5. 워커가 아닌 세션이 끝날 때 다른 세션에 알리는 Orca 수단(문서에 없음)
6. 플러그인 `agent.status.changed` 의 `done` 의미, chat 에이전트 포함 여부, 이 머신의 플러그인 시스템 상태
7. 세션이 자기 터미널을 닫는 방법·안전성, chat 세션의 자기 종료
