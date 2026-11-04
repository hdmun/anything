---
status: accepted
---

# 감독은 Orca 의 깨우기를 따르고, relay 는 폴링·멈춤 타이머를 두지 않는다

Orca 1.4.247 가이드는 워커를 띄운 뒤 턴을 끝내면 Orca 가 진행자를 깨운다고 하고, 폴링(`check` 반복·감시 스크립트)을 금지한다. relay 의 감독 보강(`check --wait 600000` 루프와 빈 대기 1~3층, `liveness`·`startup` 결정기, 화면 확인창 감지 `BLOCKED_RE`, 기동 실패 예산 2)은 그 폴링 루프 위에 서 있었다. 그래서 **relay 는 감독 보강을 모두 지우고 Orca 의 깨우기와 영수증(`state`·`failedStage`·`next`, `recovery-and-cleanup`)을 따른다.** relay 에 남는 감독 정책은 세 줄이다.

- `agent_prompt_blocked` 면 사람을 부른다. 진행자는 키를 보내지 않는다.
- `outcome_unknown` 이면 스스로 재출발하지 않고 사람을 부른다(같은 Task 를 두 워커가 하는 것을 막는다).
- `escalation` + `stopReason` 이면 spec 의 해당 절을 근거로 `send` 로 한 번 다시 지시한다. 같은 워커가 두 번째 멈추면 멈춤 보고(ADR 0008). 다시 지시는 라운드로 세지 않는다.

기동 실패는 Orca 의 3회 circuit-break 가 끝이고, breaker 가 걸리면 멈춤 보고다. 기동 실패를 라운드로 세지 않는 규칙은 그대로다.

## Considered Options

- **`check --wait` 루프를 유지하고 「Orca 기본과 다른 점」에 근거를 적는다**: 루프의 `check` 가 메일을 가져가 Orca 가 깨울 근거를 없앤다. 가이드가 명시적으로 금지한다. 기각.
- **멈춤 타이머(구현 5분·리뷰 10분)를 주기적 자기 깨우기로 살린다**: 그것이 곧 폴링이다. 타이머의 판정은 원래 `human` 하나뿐이었고, Orca 도 침묵은 아무것도 증명하지 않는다고 한다. 기각 — 살아 있지만 조용한 워커는 사람이 Orca UI 로 본다.
- **`BLOCKED_RE` 로 작업 중 화면 확인창을 계속 본다**: 근거였던 T-007 의 창은 샌드박스를 켠 codex 의 명령 승인창이었다. `worker-start` 의 codex 는 설정과 상관없이 yolo 로 떠서 그 창이 생기지 않는다(2026-11-04 실측). 기동 때의 확인창은 Orca 준비 단계가 `agent_prompt_blocked` 로 잡는다. 기각.
- **기동 실패 예산 2 를 유지한다**: 「3번째는 마지막 기회」라는 근거는 1.4.247 에서 사용자가 breaker 뒤에 같은 Task 를 다시 열 수 있어 약해졌다. 기각.

## Consequences

- `references/wait.md`, `relaylib/orca.py` 의 `startup`·`liveness`(와 `BLOCKED_RE`·`STALL_MS`·`STARTUP_BUDGET`), 그 CLI 하위 명령·테스트, eval 케이스 `startup-no-dispatch` 가 지울 대상이 된다. `delivery-failed`·`update-prompt-blocked` 는 남는 정책(재출발 금지·키 금지)을 시험하므로 `outcome-unknown`·`prompt-blocked` 로 다시 쓴다.
- 조용히 멈춘 워커는 relay 가 감지하지 않는다. 이 공백이 실제로 문제가 되면 relay 가 아니라 Orca 에 기능을 요청한다.
- 작업 중 승인창이 다시 관측되면(예: codex 가 yolo 가 아닌 모드로 뜨게 바뀜) 이 결정을 다시 연다.
- codex 사전 조건(`check_for_update_on_startup = false`, `tui.terminal_title`)은 기동 때의 확인창·준비 timeout 을 막는 예방책이라 남는다.
