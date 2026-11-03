# Orca 1.4.245 가 relay 감독 보강을 대신하는가

- 이슈: hdmun/anything#13 (지도 #11, 처분은 #15)
- 조사일: 2026-11-03
- 대상: `plugins/relay/scripts/relaylib/orca.py` 의 `startup`(38행)·`liveness`(83행)
- 기준 버전: Orca 데스크톱 1.4.245. `orca --version` = `1.4.245`. 소스 태그 `v1.4.245` = `1c6ac8c3c4`(2026-10-30, `release: v1.4.245`, `package.json` version `1.4.245`). 설치본 `orca orchestration worker-start --help`·`worker-show --help` 문구가 소스 `src/cli/specs/orchestration-worker-specs.ts` 49·59행과 같다.

## 출처

| 약칭 | 내용 |
| --- | --- |
| `v1.4.245:<경로>:<줄>` | Orca 소스 `C:\Users\hdmun\repo\ref\orca` 의 태그 `v1.4.245`. `git show`·`git grep` 으로만 읽었다 |
| [guide] | `orca skills get orchestration`(= `v1.4.245:skill-guides/orchestration.md`), `--reference references/recovery-and-cleanup.md`(= `v1.4.245:skill-guides/orchestration/references/recovery-and-cleanup.md`). 줄 번호는 소스와 설치본 출력이 같다 |
| [plan] | `plugins/relay/docs/plan.md` |
| [fx] | `plugins/relay/tests/fixtures/orca/` |
| [local] | 이 PC 의 설정 파일(읽기만): `~/.gemini/config/hooks.json`, `~/.codex/hooks.json` |

**사실**은 소스·가이드·기존 측정에서 옮긴 것이다. **추론**은 그것을 relay 에 적용한 판단이다. 이번 조사에서는 워커·Run 을 띄우지 않았다.

## 요약

| # | 상황 | 판정 | 한 줄 근거 |
| --- | --- | --- | --- |
| 1 | 기동 실패 영수증 | 대신한다 | 실패면 `ok: true`(RPC 봉투) + `result.state: failed` + `failedStage` + 종료코드 1. 감지는 Orca 가 다 준다 |
| 2 | agy 생존 판정 | 실측 필요 | 1.4.245 에 agy hook → fleet `live (agent_status)` 경로가 있다. `missing_status` 는 1.4.245 에서 잰 적이 없다. 멈춤 타이머는 Orca 에 없다 |
| 3 | 확인창 감지 | 일부만 | 화면 sentinel 은 `worker-show` `agentWait`(source `prompt-text`)과 `worker-start` 준비 단계까지 이어진다. `worker-list` `projection.attention` 에는 이어지지 않는다 |
| 4 | 전달 미확인 | 일부만 | `outcome_unknown` 영수증, `nextCommands`, 늦은 보고 정산, `--retry-of` 차단은 준다. "입력이 전달됐는가"는 판정하지 않는다 |

---

## 1. 기동 실패 영수증

### 사실

- **종료코드.** CLI 핸들러는 `result.state !== 'ready'` 이면 `process.exitCode = 1` 로 두고, 응답은 그대로 출력한다 — `v1.4.245:src/cli/handlers/orchestration/worker-launch-handler.ts:73-75`, `:87`.
- **`ok`.** `--json` 출력은 RPC 성공 봉투 전체다 — `v1.4.245:src/cli/format.ts:69-79`. 성공 봉투의 `ok` 는 타입상 항상 `true` 다 — `v1.4.245:src/shared/runtime-rpc-envelope.ts:51-54`.
- **help 문구.** "The call exits 0 only for ready. Failed or outcome_unknown exits 1 and JSON includes stage/failedStage, setup, effects, residualResources, and recovery commands when needed." — `v1.4.245:src/cli/specs/orchestration-worker-specs.ts:49`(설치본 help 49행과 같다).
- **실패 영수증 모양** — `v1.4.245:src/main/runtime/rpc/methods/orchestration/worker/worker-start-receipt.ts:76-112`:
  - `dispatchId`, `state`(`failed`, 결과를 모르면 `outcome_unknown`), `stage`, `failedStage`, `lastError`(예외 메시지), `effects`, `residualResources`
  - 이 기동이 만든 터미널이 남았으면 `recovery`: "This start created a terminal that never ran the Task. Close it with: orca orchestration worker-release --dispatch <id>"
  - 결과를 모르면 `nextCommands`: `worker-show`, `worker-abandon`
- **`failedStage` 값과 `lastError`.**
  - 단계: `terminal_create` → 배치 → `setup_start` → `agent_readiness` → `setup_wait` — `v1.4.245:src/main/runtime/rpc/methods/orchestration/worker/local-worker-start.ts:187-257`. 이어서 `dispatch_input`, `turn_observation` — `v1.4.245:src/main/runtime/rpc/methods/orchestration/worker/worker-start-readiness-settlement.ts:51`, `:55`, `:80`.
  - `agent_readiness` 실패: 확인창이면 `Agent startup blocked: <reason>`, 아니면 `Agent did not become ready (<status>).` — `local-worker-start.ts:245-258`.
  - 입력을 쓰기 직전 권한 대기: 예외 `agent_prompt_blocked` → `failedStage: dispatch_input` — `v1.4.245:src/main/runtime/terminal/input/terminal-agent-prompt.ts:79-83`, `:141-144`, `:186`, `v1.4.245:src/main/runtime/terminal/wait/terminal-wait-permission.ts:315-322`.
  - `outcome_unknown` 로 분류되는 실패: 오류 코드 `operation_unknown`, 또는 `worktree_create` 단계의 연결 끊김·시간 초과 — `v1.4.245:src/main/runtime/rpc/methods/orchestration/worker/worker-topology.ts:193-206`.
- **Task·예산.** `failWorkerStart` 는 Dispatch `failure_count` 를 1 올리고 3회째에 `circuit_broken` 으로 만든다. 다른 활성 Dispatch 가 없으면 Task 를 `failed` 로 만든다 — `v1.4.245:src/main/runtime/orchestration/db/worker-dispatch/worker-dispatch-outcome.ts:44-96`, 임계 `v1.4.245:src/main/runtime/orchestration/db/dispatch-context/dispatch-circuit-breaker.ts:1`(= 3).
- **가이드.**
  - "If `worker-start` exits non-zero, do not relaunch. Read the receipt's `failedStage` and `residualResources`, then load `references/recovery-and-cleanup.md`." — [guide] `orchestration.md:122-124`
  - 증명된 `failed` → `--retry-of` 로 replacement. 3회 실패면 circuit-break, `--retry-of` 는 `task_not_startable` 로 거부 — [guide] `recovery-and-cleanup.md:9`, `:110-125`

### 판정: 대신한다

- 티켓 질문의 답: `failedStage` 가 있으면 **`ok: true`, 종료코드 1, `result.state: "failed"`** 다. relay 의 가정(`ok: true` + `failedStage`, poker-server T-005)과 Orca kernel 의 "exits non-zero" 는 둘 다 맞다. 서로 충돌하지 않는다.
- 실패 감지는 Orca 가 세 가지(종료코드, `state`, `failedStage`)로 준다. relay `startup` 의 `failedStage` 판독은 감지로서는 중복이다.
- Orca 가 주지 않는 것은 대응 정책이다.
  - relay 예산 2(`orca.py:17`). Orca 는 3회째에 끊는다.
  - `agent_prompt_blocked` → 사람(`orca.py:50-51`). Orca 가이드는 `failed` 면 `--retry-of` 를 허용한다.
- 관련 relay: `orca.py:38-55`, `plugins/relay/skills/relay/references/implementer.md:51`(표 64행), [plan] 45행.
- 주의: [fx] `worker-start-readiness-failed.json`·`worker-start-prompt-blocked.json` 은 2.0.0 이전 경로의 모양이다(`dispatch: null`, `state`·`dispatchId`·`residualResources` 없음, `lastError: "timeout"`). 1.4.245 실패 영수증은 위 필드를 가진다. 1.4.245 실패 영수증의 실제 JSON 은 아직 실측으로 남지 않았다. 이 판정은 소스와 설치본 help 로 했다.

---

## 2. agy 생존 판정

### 사실

- **fleet liveness** — `v1.4.245:src/shared/orchestration-fleet-worker-projection.ts:53-100`:
  - 종료 증거가 없고 그 워커에 묶인 agent-status 증거도 없으면 `unverifiable / missing_status`(76-78행).
  - 증거가 30분 안이면 `live / source: agent_status`(96-99행). 30분을 넘으면 `unverifiable / stale_status`. 임계는 `v1.4.245:src/shared/agent-status-freshness.ts:4`(= 30분).
- **nextAction** — 같은 파일 167-179행: `live` + `workerState: ready` → `none`, `unverifiable` → `none`. 살아 있어도 실행할 argv 는 없다.
- **attention** — `v1.4.245:src/shared/orchestration-fleet-attention.ts:33-40`, `:62-67`: `unverifiable` 이면 `unverifiable` 범주가 붙고 `requiresAction: true` 가 된다. 그래도 argv 는 없다.
- **agy 상태 hook 이 1.4.245 에 있다.**
  - `v1.4.245:src/shared/agent-hook-listener/providers/antigravity-events.ts:21-111`: `PreInvocation`·`PostInvocation`·`PreToolUse`·`PostToolUse` → `working`, `ask_question`·`ask_permission` 도구 → `waiting`, 바쁘지 않은 `Stop` → `done`.
  - Orca 는 이 hook 을 `~/.gemini/config/hooks.json` 에 설치한다 — `v1.4.245:src/main/antigravity/hook-service.ts:42`. [local] 이 PC 의 그 파일에 `orca-status` 묶음 5개 이벤트가 들어 있다(2026-10-22 수정).
  - 턴 시작 관측도 hook 으로 한다: `HOOK_OBSERVED_TURN_START_AGENTS = {antigravity, codex, kimi}` — `v1.4.245:src/main/runtime/agent-prompt-submission-verification.ts:7`.
  - 2026-11-02 실측 영수증 [fx] `worker-start-agent-agy.json`: `turnStart: observed`, `prompt.provider: antigravity`, `prompt.observation: supported`. 그 PTY 에 agy hook 이 도착했다는 뜻이다.
- **relay 의 근거.** "`liveness: unverifiable (missing_status)`, `nextAction: none`" 은 트랙 1(v1.1.2)의 관찰이다. 그때 경로는 `terminal create --command '$null=1; agy'` + `worker-start --terminal` 이었다 — [plan] 20행, `plugins/relay/skills/relay/references/wait.md:43`. 1.4.245 `worker-start --agent antigravity` 경로에서 `worker-list` projection 을 잰 기록은 없다([plan] 137-157행 표에 없다).
- **멈춤 타이머는 Orca 에 없다.**
  - "Leave the wait only on positive proof the agent stopped" — [guide] `orchestration.md:156-161`
  - `unverifiable`, null `agentWait`, 안 바뀐 `worker-read` 꼬리는 모두 부재다. 부재는 stop·abandon·retry·release 를 허락하지 않는다 — [guide] `recovery-and-cleanup.md:52-63`
  - 30분 `stale_status` 는 판정을 `unverifiable` 로 내릴 뿐 행동을 주지 않는다.
- **worker-show 가 더 나은 경우.** `missing_status`·`host_unavailable`·`capability_unsupported` 는 이 클라이언트 쪽 공백이다. 이때는 실행 호스트가 준 `worker-show` 판정이 fleet 행보다 나은 증거다 — [guide] `recovery-and-cleanup.md:33-45`.

### 판정: 실측 필요

- 소스상 1.4.245 의 agy 워커는 hook 이 묶이면 `live (agent_status)` 를 받는다. 실제로 묶이는지는 fleet 증거의 binding 규칙(`v1.4.245:src/shared/orchestration-fleet-status-index.ts:45-60`, `:103-120`)에 달려 소스만으로 확정할 수 없다.
- 결과가 어느 쪽이든 **멈춤 5분·10분 뒤 사람 호출은 Orca 가 대신하지 못한다.** 그런 기능이 없다. 사람 호출은 상태를 바꾸지 않으므로 Orca 의 안전 바닥과 충돌하지는 않는다.
- 관련 relay: `orca.py:18`, `orca.py:98-109`, `plugins/relay/skills/relay/references/wait.md:41-43`.

### 실측 방법

버리는 Run, 새 에이전트 탭 = 터미널.

1. `worker-start --spec "<파일 몇 개를 읽고 60초 기다린 뒤 worker_done>" --worktree <relay-smoke> --agent antigravity --json`
2. 작업 중 2~3회, `worker_done` 직후 1회 기록한다.
   - `worker-list --run <run_id> --include-remote --json` 의 그 행: `projection.liveness`(verdict·reason·source), `nextAction`, `attention`, `stage.activity`, `evidence.liveStatus`
   - 같은 시각 `worker-show --dispatch <id> --json` 의 `observation`
3. 판단: `live / agent_status` 면 relay 문서의 "agy 는 2층이 답을 주지 않는다"는 낡은 서술이다. `missing_status` 면 그대로다.

---

## 3. 확인창 감지

### 사실

- **sentinel 의 현재 이름.** `TERMINAL_WAIT_BLOCKED_SENTINEL_RE` 는 1.4.245 에 없다. 같은 역할은 `BUILT_IN_SENTINEL_RE` 에 에이전트 규칙의 차단 anchor 를 합친 `terminalWaitBlockedSentinelRe` 다 — `v1.4.245:src/main/runtime/agent-state-rules/blocked-text-layer.ts:14-24`. 화면 맨 아래의 비어 있지 않은 12줄만 본다(26-45행).
  - `press enter to confirm|continue|view|insert` 앞뒤 600자에 `codex`·`permission`·`sandbox`·`trust`·`hook` 이 있으면 `agent-interactive-prompt` — 같은 파일 77-102행
  - `permission required` 뒤에 선택지가 2개 이상이면 같은 이유 — 105-119행
  - 시작 대화창(update·cwd·model migration·hooks review) — `v1.4.245:src/main/runtime/startup-dialog-blocked-signals.ts:34-60`
- **relay `BLOCKED_RE`(`orca.py:24-31`)와 비교.**
  - Orca 에 없는 것: `run this command\?`, `\bsign in\b`, `would you like to run the following command`, `yes, proceed`, `don't ask again`
  - T-007 화면([fx] `codex-screen-approval.txt`)은 `Press enter to confirm` 과 `Codex` 를 담고 있다. Orca 규칙으로도 `agent-interactive-prompt` 다.
- **화면 → 감지 시각.** PTY 출력을 주기적으로 훑어 새 차단 이유가 생기면 `waitBlockedAt` 을 찍는다 — `v1.4.245:src/main/runtime/terminal/wait/terminal-wait-blocked-checks.ts:85-116`, `v1.4.245:src/main/runtime/terminal/output/pty-output-ingestion.ts:233-235`.
- **→ `worker-show` `observation.agentWait`.**
  - 정확히 그 워커 프로세스일 때만 `terminal.agentWait` 를 싣는다 — `v1.4.245:src/main/runtime/rpc/methods/orchestration/worker/worker-observation.ts:76-91`, `:140-148`.
  - 값의 출처는 `prompt-text`(화면 sentinel), `title`(제목이 permission), `hook`(hook 상태가 permission) 셋이다 — `v1.4.245:src/main/runtime/terminal/wait/terminal-interactive-wait.ts:72-113`.
  - 조건 — `v1.4.245:src/main/runtime/terminal/wait/terminal-wait-permission.ts:128-166`:
    - 살아 있는 제목이 permission 이 아닌 상태(working 등)를 말하면, `agent-approval-prompt` 를 뺀 차단 문구는 지운다(138-149행).
    - 그 밖에는 permission 증거(`waitBlockedAt`·hook·lifecycle)가 해제 증거보다 새로워야 한다(153-165행).
  - help: "Null means Orca looked and found no wait. An absent field means it never looked …" — `v1.4.245:src/cli/specs/orchestration-worker-specs.ts:59`
- **→ `worker-start` 영수증.**
  - 준비 대기 중 확인창 → `failedStage: agent_readiness`, `lastError: "Agent startup blocked: <reason>"` — `local-worker-start.ts:245-258`
  - 입력을 쓰기 직전 권한 대기 → `failedStage: dispatch_input`, `lastError: agent_prompt_blocked`(1절)
  - 입력을 쓴 뒤 권한 대기 → `turnStart: "permission"`, `state: ready`, 종료코드 0 — `v1.4.245:src/main/runtime/orca-runtime-agent-prompt-request-correlation.ts:81-84`, `terminal-agent-prompt.ts:300-305`, `v1.4.245:src/main/runtime/rpc/methods/orchestration/worker/worker-start-turn-observation.ts:16-28`, `worker-start-readiness-settlement.ts:107`, `:148-160`
- **→ `worker-list` `projection.attention`: 이어지지 않는다.**
  - `pendingInput` 은 오케스트레이션 질문(`question_threads` 의 pending), `pendingApproval` 은 decision gate(`decision_gates` 의 pending)다 — `v1.4.245:src/main/runtime/orchestration/db/worker-terminal/worker-terminal-attention-query.ts:46-58`.
  - attention 범주는 이 둘과 outcome·interruption·liveness 로만 만든다 — `v1.4.245:src/shared/orchestration-fleet-attention.ts:42-84`. 화면 sentinel 과 `agentWait` 은 입력이 아니다.
  - 다만 신선한 hook 상태는 `projection.stage.activity` 에 실린다(`waiting` 등) — `orchestration-fleet-worker-projection.ts:232-237`. agy `ask_permission`(`antigravity-events.ts:61-64`)과 codex `PermissionRequest`(`v1.4.245:src/shared/agent-hook-listener/providers/codex-events.ts:133-150`, 자동 리뷰가 맡으면 `working`)가 `waiting` 이 된다.
- **예방.**
  - Orca 가 띄우는 워커의 yolo 인자: codex `--dangerously-bypass-approvals-and-sandbox`, antigravity `--dangerously-skip-permissions` — `v1.4.245:src/shared/tui-agent-permissions.ts:12-21`. 실제로 붙는지는 Orca 권한 모드 설정에 달려 있다.
  - 2026-11-02 측정: agy trust·codex 업데이트 확인창 재현 불가, codex 4/4 막힘 없음 — [plan] 141-148행.
- T-007(`agentWait` 이 비어 있었다)은 2.0.0 이전 경로의 실측이다. 그때는 Orca 1.4.222 무렵이고 리뷰어를 터미널 선기동으로 띄웠다 — [plan] 277-284행.

### 판정: 일부만

- sentinel 은 `worker-show` `agentWait`(source `prompt-text`)과 `worker-start` 준비 단계(`Agent startup blocked`)까지 이어진다.
- `worker-list` `projection.attention` 에는 이어지지 않는다. 확인창 신호로 attention 을 볼 수는 없다.
- 작업 중 확인창에서 1.4.245 `worker-show` 가 실제로 `agentWait` 을 채우는지는 실측이 없다([plan] 382행 「미검증」 그대로).
- 관련 relay: `orca.py:22-31`, `orca.py:90-95`, `plugins/relay/skills/relay/references/wait.md:18`, `:42`, `:48-49`.

### 실측 방법

1. 버리는 Run 에서 codex 워커가 승인창에 서게 만든다. Orca 설정의 codex 권한 모드를 잠시 yolo 가 아닌 것으로 바꾸고 `worker-start --agent codex --spec "git status --short 를 실행하고 worker_done" --json`. 사용자 설정을 바꾸는 일이므로 끝나면 되돌린다. 승인창에 자동 응답하지 않는다.
2. 기록한다.
   - `worker-start` 영수증의 `turnStart`·`state`
   - 창이 떠 있는 동안 `worker-show --json` 의 `observation.agentWait`
   - `terminal show` 의 제목과 `agentWait`
   - `worker-list --run <run_id> --json` 의 `attention`·`stage.activity`·`nextAction`
   - `worker-read --json` 의 `source` 와 꼬리
3. 판단: `agentWait` 이 `prompt-text` 나 `hook` 으로 채워지면 relay 의 화면 검사와 같은 신호다. `null` 이면 제목 규칙(138-149행)이 지운 것인지 제목 값으로 확인한다.

---

## 4. 전달 미확인

### 사실

- **관측 시간.** 입력을 쓴 뒤 턴 시작을 최대 30초 본다 — `AGENT_PROMPT_EFFECT_TIMEOUT_MS`, `v1.4.245:src/shared/orchestration-timing-budgets.ts:3`(클라이언트 유예 50초, 7행). 관측을 지원하는데 못 보면 `unobserved` 다: "unverifiable, never dead, and no safe blind resend" — `worker-start-turn-observation.ts:5-7`, `:16-28`.
- **영수증** — `worker-start-readiness-settlement.ts:107-146`:
  - `state: outcome_unknown`, `stage: turn_start_unobserved`, `turnStart: unobserved`, `lastError`, `residualResources`
  - `nextCommands`: `worker-show --dispatch <id> --json`, (터미널 워커면) `terminal read --terminal <handle> --screen`, `worker-abandon --dispatch <id> --json`
  - 종료코드 1 — `worker-launch-handler.ts:73-75`
- **`lastError` 문구.** "…check with `terminal read` before resending. This is unverifiable, not proof the worker is dead. If the worker recovers and reports, this Dispatch settles normally." — `worker-start-turn-observation.ts:62-70`
- **DB 상태** — `worker-dispatch-outcome.ts:107-144`: worker `start_unknown`, Task `blocked`, **Dispatch 상태는 그대로 `pending`**.
  - Dispatch 가 `pending` 을 벗어나는 길은 둘뿐이다. 준비 확정(`markWorkerDispatchReady`, 같은 파일 8-25행)과 워커 보고(`v1.4.245:src/main/runtime/orchestration/db/dispatch-context/worker-report-settlement.ts:205-215`)다.
  - `start_unknown` 워커도 보고할 수 있다 — `v1.4.245:src/main/runtime/orchestration/worker-report-admission.ts:6`.
- **중복 방지.** `--retry-of` 는 이전 워커가 `failed`·`stopped`·`abandoned` 일 때만 받는다 — `v1.4.245:src/main/runtime/orchestration/db/worker-dispatch/worker-dispatch-start.ts:109-125`. `start_unknown` 인 채로는 재출발이 `task_not_startable` 로 거부된다.
- **projection.** `start_unknown` + `live` → `nextAction: inspect`(`worker-show`). `unverifiable` → `none` — `orchestration-fleet-worker-projection.ts:167-183`.
- **가이드.**
  - `outcome_unknown` → "Inspect, then choose `worker-stop` or explicit `worker-abandon`" — [guide] `recovery-and-cleanup.md:10`, `:127-132`
  - `request-show` 는 응답을 잃어 Dispatch 를 모를 때 쓴다 — `recovery-and-cleanup.md:74-90`. 이 영수증은 Dispatch 를 준다.
  - 입력은 받아졌는데 제출이 불확실하면 `terminal send --wait-submit <초>` — `recovery-and-cleanup.md:92-94`

### 판정: 일부만

- Orca 가 주는 것: 실패로 단정하지 않는 상태(`outcome_unknown`), 살펴볼 명령(`nextCommands`), 늦은 보고의 정상 정산, `--retry-of` 차단으로 같은 Task 에 워커 둘이 붙는 것을 막기.
- Orca 가 주지 않는 것: "입력이 전달됐는가"의 판정, 기다릴 시간, 사람을 부를 시점. 이것은 진행자가 살펴보고 정한다.
- relay 기준(60초 뒤 `dispatch-show` 가 `pending` 이면 전달 실패)은 1.4.245 의미와 맞지 않는다. `pending` 은 "아직 보고가 없다"는 뜻이다. 정상으로 작업 중인 워커도 `worker_done` 전까지 `pending` 이다.
- 관련 relay: `orca.py:60-63`, `plugins/relay/skills/relay/references/implementer.md:62`, `plugins/relay/skills/relay/SKILL.md:73`, [plan] 311행.

---

## relay 적용(추론)

> 이 절은 **추론**이다. 위 사실을 relay 코드에 대 본 판단이며, 지울지는 [#15](https://github.com/hdmun/anything/issues/15) 가 정한다.

1. **`startup` 감지.** 종료코드나 `result.state` 만으로 실패를 알 수 있다. `failedStage` 판독은 남겨도 해가 없다. 빈틈이 둘 있다.
   - 준비 단계 확인창(`lastError` 가 `Agent startup blocked:` 로 시작)은 지금 `retry` 로 간다. `orca.py:50` 은 `agent_prompt_blocked` 만 본다. 같은 창에 한 번 더 막혀 예산을 쓴 뒤에야 사람에게 간다.
   - `turnStart: "permission"`(`state: ready`, 종료코드 0)은 지금 `ok` 로 간다. 입력 직후 권한 대기라 사람이 필요할 수 있다.
   - 픽스처 `worker-start-readiness-failed.json`·`worker-start-prompt-blocked.json` 은 1.4.245 모양으로 바꿀 필요가 있다.
2. **`liveness` 2층(projection).** 2절 실측이 `live / agent_status` 를 보이면 `wait.md:43` 은 낡은 서술이다. 다만 `live` 여도 작업 중 `nextAction` 은 `none` 이다. `run_argv` 분기는 정산 뒤 `release` 같은 경우에만 쓰인다.
3. **`liveness` 3층(멈춤 5·10분).** Orca 에 대응 기능이 없다. 남길지는 relay 정책 문제다. Orca 가이드가 `missing_status` 일 때 더 낫다고 하는 `worker-show` `observation.status` 를 지금 relay 는 보지 않는다.
4. **화면 `BLOCKED_RE`.** `agentWait`(`prompt-text`)이 같은 계열의 sentinel 로 같은 화면을 본다. 3절 실측에서 `agentWait` 이 채워지면 relay 의 화면 검사는 중복이다. 채워지지 않으면(제목 규칙이 지우는 경우) 화면 검사가 유일한 신호로 남는다. T-007 에서 `agentWait` 이 비었던 것도 이 제목 규칙 때문일 수 있다 — 확인하지 못했다. `projection.attention` 은 어느 경우에도 확인창 신호가 아니다.
5. **`confirm_delivery`.** `pending` 기준은 거짓 양성을 낸다. 정상 작업 중인 워커를 전달 실패로 볼 수 있다. 사람 호출로 끝나므로 위험하지는 않다. Orca 의 `nextCommands`(`terminal read --screen`, `worker-show`)가 더 직접적인 증거다. "스스로 재출발하지 않는다" 규칙은 Orca 의 `--retry-of` 차단과 겹친다.

## 확인하지 못한 것

- 1.4.245 실패 영수증의 실제 JSON(1절은 소스와 help 로 판정했다).
- agy hook 행이 fleet 증거로 그 워커에 묶이는지(2절 실측).
- 작업 중 확인창에서 `agentWait` 이 채워지는지, 제목 규칙이 지우는지(3절 실측).
- T-007 에서 `agentWait` 이 비었던 원인.
- 빌드 스위치 `ORCA_LAYOUT_OWNER_IS_MAIN` 에 따른 `worker-show` 판정 분기(`worker-observation.ts:107-129`)는 따라가지 않았다.
