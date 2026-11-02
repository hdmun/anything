# 대기와 무응답 판정 (e)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (대기)

## (e) 대기와 무응답 판정

- `orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 600000 --json`
- **stdout만 파이프할 것.** `--wait` 중 stderr로 keepalive(`{"_keepalive":true}`)가 나오므로 `2>&1`로 합치면 파서가 깨진다.
- `question`이 오면 답하고 다시 대기한다. 순서는 다음과 같다:

```bash
# 1) question 수신 — 응답에서 msg_id 와 deliveryId 를 모두 뽑아둔다
orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 600000 --json

# 2) 답변
orca orchestration reply --id <msg_id> --body "<답>" --json

# 3) ack 와 재대기를 한 번에 — 이 delivery 를 ack 하지 않으면 같은 배치가 재전달된다
orca orchestration check --ack <delivery_id> --wait --types worker_done,escalation,question --timeout-ms 900000 --json
```

  워커의 질문에 답할 때는 **판단의 근거까지 적는다.** 워커는 spec과 역할 파일만 알고 이 대화를 모르므로, "승인"만 보내면 다음 유사 상황에서 또 물어본다. 어느 spec 항목에 근거했는지, 그 발견을 finding으로 올릴지 말지까지 함께 지시한다.

### 빈손으로 돌아왔을 때

**빈 대기와 타임아웃은 실패가 아니라 체크포인트다.** 순서대로 내려간다.

**1층 — 빈 대기마다 화면만 본다. 3회 미만이면 다시 기다린다.** heartbeat나 화면 활동은 *살아 있다*는 뜻이지 *끝났다*는 뜻이 아니다.
그러나 확인창에서 멈춘 워커는 기다려도 끝나지 않는다. 그래서 **1회째부터** 화면을 `liveness`에 넘긴다 — 확인창이면 그 자리에서 `human / blocked_prompt`가 나온다.
실측(T-007): codex 리뷰어가 `git status --short`·`Get-Location` 승인창에서 멈췄는데 `agentWait`은 비어 있었다. 빈 대기 2회 뒤 화면을 읽고서야 알았다.

```bash
orca terminal read --terminal <worker handle> --screen --json > screen.json
orca terminal show --terminal <worker handle> --json > term.json
python "$RELAY/scripts/relay_cli.py" liveness --screen screen.json --terminal term.json --empty-waits <연속 빈 대기 횟수> --role implementer|reviewer
```

`wait`(`reason: layer1`)이면 `check --wait`를 다시 건다.

**2·3층 — 3회 연속 빈 대기면 fleet projection도 함께 넘긴다.**

```bash
orca orchestration worker-list --run <run_id> --include-remote --json > workers.json   # 그 워커 항목만 남겨도 된다
python "$RELAY/scripts/relay_cli.py" liveness --worker workers.json --screen screen.json --terminal term.json --empty-waits 3 --role implementer|reviewer
```

| `action` | 할 일 |
|---|---|
| `run_argv` | projection이 다음 행동을 줬다(`attention.requiresAction`). `argv`를 그대로 실행한다 — `orca` 접두는 이미 붙어 있다 |
| `wait` | 작업 중이다. 1층으로 돌아가 계속 대기 |
| `human` | `prompt_wait`(`agentWait` — 자동 응답 금지), `blocked_prompt`(화면의 확인창 — 자동 응답 금지), `stalled`(출력 정지: 구현 5분·리뷰 10분), `exited`(워커 종료) |

- **2층(projection)이 1차 신호**이고 3층(`lastOutputAt` 벽시계)은 projection이 답을 못 줄 때만 쓴다. 정본은 3층에서 *"`liveness.reason`을 읽고 계속 기다려라"* 라고만 해서 종료 조건이 없다 — relay가 임계값을 둔 이유다.
- **agy 워커는 2층이 답을 주지 않는다.** 실측(T-004): `liveness: unverifiable (missing_status)`, `nextAction: none`만 돌아왔다. `liveness`는 이 경우 자동으로 3층으로 내려간다.
- 임계값과 판정 순서의 정본은 `scripts/relaylib/orca.py`다.
**사람 호출은 상태를 바꾸지 않으므로 안전한 종료 조건이다.** 정본이 금지하는 것은 부재를 근거로 `stop`·`abandon`·`retry`·`release`하는 것이지, 사람을 부르는 것이 아니다.

**`agentWait`는 양성 신호로만 믿는다.** 값이 있으면 실제로 멈춘 것이지만, `null`은 안 멈췄다는 증거가 아니다.
정본도 같은 말을 한다 — *"`unverifiable` is absence, including when `worker-show` reports `agentWait` null."*
실측으로도 워커가 트러스트 프롬프트에 멈춘 상태에서 `agentWait: null`을 반환한 적이 있다.
그래서 `agentWait`·`tui-idle`·heartbeat 중 **어느 것도 1차 신호가 아니다.** 2층의 projection이 1차이고, 그것이 답을 못 줄 때만 3층의 `lastOutputAt`을 본다.

**프롬프트 자동 응답은 금지한다.** `trustedWorkspaces` 사전 등록으로 알려진 프롬프트는 이미 제거했으므로, 남은 프롬프트는 예상 밖의 것이고 사람이 봐야 한다.
