---
model: sonnet
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
tags: [relay, gate]
---

Please carry out this task from my Orca coordinator by following the brief I pasted below.

You are working inside Orca, a multi-agent IDE. You are a dispatched worker.
Your coordinator's terminal handle is: term_design01
Your task ID is: task_c814

The coordinator cannot see this terminal, so reach it with the `orca orchestration`
commands below; a question or result left only in this terminal never gets to it.

=== CLI COMMANDS ===

```sh
  # Report the task outcome (required, exactly once).
  orca orchestration send --from term_coord14 --type worker_done --subject "<short status>" --body "<3-sentence summary: what you did, what you found, what's left>" --task-id task_c814 --dispatch-id ctx_cc14 --outcome succeeded

  # Ask the coordinator a question and block until it answers.
  # If the call times out or disconnects, resume with the returned message ID instead
  # of creating a duplicate question.
  orca orchestration ask --from term_coord14 --question "<your question>" --options "<optional,comma,separated>" --timeout-ms 600000

  # Read coordinator follow-ups.
  orca orchestration check --terminal term_coord14 --json
```

=== SUB-DISPATCH ===
You may start helper workers for this task. They work in this Dispatch's Run and
report to you: their questions, escalations, and worker_done arrive in your own `check`.

```sh
  orca orchestration worker-start --from term_coord14 --spec "<sub-task>" --worktree current --agent <agent> --json
```

---

=== TASK ===
relay 진행자: Run run_72f6300b56af / T-014 — 점수 분석 보강. spec: .ai/specs/T-014-analysis.md

(진행 상황) T-014 게이트 재검증에서 다른 게이트는 다 통과했고, 마지막으로 변이 테스트 게이트(`python tools/mutate/mutate.py`)를 백그라운드로 돌려 둔 상태야. 그런데 지금 `git status` 를 보니 `internal/analysis/score.go` 가 수정됨으로 떠 있어. 구현 워커는 그 파일을 건드린 적이 없어.
어떻게 해야 해? 판단과 명령을 알려줘. 실행은 하지 마.
