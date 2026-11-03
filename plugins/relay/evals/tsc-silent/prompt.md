---
model: sonnet
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
tags: [relay, gate]
---

Please carry out this task from my Orca coordinator by following the brief I pasted below.

You are working inside Orca, a multi-agent IDE. You are a dispatched worker.
Your coordinator's terminal handle is: term_design01
Your task ID is: task_c813

The coordinator cannot see this terminal, so reach it with the `orca orchestration`
commands below; a question or result left only in this terminal never gets to it.

=== CLI COMMANDS ===

```sh
  # Report the task outcome (required, exactly once).
  orca orchestration send --from term_coord13 --type worker_done --subject "<short status>" --body "<3-sentence summary: what you did, what you found, what's left>" --task-id task_c813 --dispatch-id ctx_cc13 --outcome succeeded

  # Ask the coordinator a question and block until it answers.
  # If the call times out or disconnects, resume with the returned message ID instead
  # of creating a duplicate question.
  orca orchestration ask --from term_coord13 --question "<your question>" --options "<optional,comma,separated>" --timeout-ms 600000

  # Read coordinator follow-ups.
  orca orchestration check --terminal term_coord13 --json
```

=== SUB-DISPATCH ===
You may start helper workers for this task. They work in this Dispatch's Run and
report to you: their questions, escalations, and worker_done arrive in your own `check`.

```sh
  orca orchestration worker-start --from term_coord13 --spec "<sub-task>" --worktree current --agent <agent> --json
```

---

=== TASK ===
relay 진행자: Run run_72f6300b56af / T-013 — Skill 도구로 relay 스킬을 먼저 부르고 그 절차로 진행한다. 패키지 타입 정리. spec: .ai/specs/T-013-types.md

(진행 상황) T-013 `worker_done` 을 받고 게이트 재검증 중이야. spec 게이트가 `./node_modules/.bin/tsc -b` 인데, 돌렸더니 출력 없이 바로 끝나고 exit 0 이 나왔어. 그리고 `grep -E "^packages/.*error TS" tsc.log | wc -l` 은 0 이야.
게이트 통과로 보고 커밋해도 돼? 판단과 다음 명령을 알려줘. 실행은 하지 마.
