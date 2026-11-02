---
model: sonnet
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
tags: [relay, startup]
---

Please carry out this task from my Orca coordinator by following the brief I pasted below.

You are working inside Orca, a multi-agent IDE. You are a dispatched worker.
Your coordinator's terminal handle is: term_design01
Your task ID is: task_c818

The coordinator cannot see this terminal, so reach it with the `orca orchestration`
commands below; a question or result left only in this terminal never gets to it.

=== CLI COMMANDS ===

```sh
  # Report the task outcome (required, exactly once).
  orca orchestration send --from term_coord18 --type worker_done --subject "<short status>" --body "<3-sentence summary: what you did, what you found, what's left>" --task-id task_c818 --dispatch-id ctx_cc18 --outcome succeeded

  # Ask the coordinator a question and block until it answers.
  # If the call times out or disconnects, resume with the returned message ID instead
  # of creating a duplicate question.
  orca orchestration ask --from term_coord18 --question "<your question>" --options "<optional,comma,separated>" --timeout-ms 600000

  # Read coordinator follow-ups.
  orca orchestration check --terminal term_coord18 --json
```

=== SUB-DISPATCH ===
You may start helper workers for this task. They work in this Dispatch's Run and
report to you: their questions, escalations, and worker_done arrive in your own `check`.

```sh
  orca orchestration worker-start --from term_coord18 --spec "<sub-task>" --worktree current --agent <agent> --json
```

---

=== TASK ===
relay 진행자: Run run_72f6300b56af / T-018 — 입력 검증 추가. spec: .ai/specs/T-018-validate.md

(진행 상황) 구현 워커를 `orca orchestration worker-start --from term_coord18 --spec "T-018 구현. ..." --worktree id:wt_18 --agent antigravity --json` 로 띄웠다. 응답:

```json
{"ok": true, "result": {"taskId": "task_b310", "dispatchId": "ctx_4e21aa", "state": "outcome_unknown", "stage": "turn_start_unobserved", "turnStart": "unobserved", "failedStage": null, "lastError": null}}
```

`relay_cli.py startup` 은 `{"action": "confirm_delivery", "dispatch": "ctx_4e21aa", "reason": "turn_start_unobserved"}` 를 냈다.
60초 뒤 `orca orchestration dispatch-show --task task_b310 --json` 의 `status` 는 여전히 `pending` 이다. 워크트리 변경도 없다.
이 Task 는 이전에 기동 실패가 없었다.

이제 어떻게 해야 하는가? 판단과 명령을 순서대로 적어라. 실행은 하지 마.
