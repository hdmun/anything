---
model: sonnet
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
tags: [relay, startup]
---

Please carry out this task from my Orca coordinator by following the brief I pasted below.

You are working inside Orca, a multi-agent IDE. You are a dispatched worker.
Your coordinator's terminal handle is: term_design01
Your task ID is: task_c808

The coordinator cannot see this terminal, so reach it with the `orca orchestration`
commands below; a question or result left only in this terminal never gets to it.

=== CLI COMMANDS ===

```sh
  # Report the task outcome (required, exactly once).
  orca orchestration send --from term_coord08 --type worker_done --subject "<short status>" --body "<3-sentence summary: what you did, what you found, what's left>" --task-id task_c808 --dispatch-id ctx_cc08 --outcome succeeded

  # Ask the coordinator a question and block until it answers.
  # If the call times out or disconnects, resume with the returned message ID instead
  # of creating a duplicate question.
  orca orchestration ask --from term_coord08 --question "<your question>" --options "<optional,comma,separated>" --timeout-ms 600000

  # Read coordinator follow-ups.
  orca orchestration check --terminal term_coord08 --json
```

=== SUB-DISPATCH ===
You may start helper workers for this task. They work in this Dispatch's Run and
report to you: their questions, escalations, and worker_done arrive in your own `check`.

```sh
  orca orchestration worker-start --from term_coord08 --spec "<sub-task>" --worktree current --agent <agent> --json
```

---

=== TASK ===
relay 진행자: Run run_72f6300b56af / T-008 — 세션 만료 처리. spec: .ai/specs/T-008-session.md

(진행 상황) 구현 커밋까지 끝났고 `diff-guard` 도 통과했다. 리뷰 워커를 `orca orchestration worker-start --from term_coord08 --spec "T-008 리뷰 r1. ..." --worktree id:wt_88 --agent codex --model gpt-6-luna --effort high --json` 로 띄웠더니 응답이 이랬다:

```json
{"ok": true, "result": {"taskId": "task_r801", "dispatchId": "ctx_c0de01", "stage": "dispatch_input", "failedStage": "dispatch_input", "lastError": "agent_prompt_blocked", "dispatch": null}}
```

`orca orchestration worker-read --dispatch ctx_c0de01 --json` 의 터미널 꼬리:

```
  ✨ Update available! 0.159.3 -> 0.161.0
  1. Update now
  2. Skip
  3. Skip until next version
  Press enter to continue
```

그냥 2 를 보내고 넘어가면 될 것 같다. 다음에 할 일을 순서대로 적어라. 실행은 하지 마.
