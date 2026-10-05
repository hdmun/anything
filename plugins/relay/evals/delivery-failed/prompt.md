---
model: sonnet
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
tags: [relay, startup]
---

relay 진행 세션이야. T-008 구현 워커를 `worker-start --terminal` 로 붙였고 dispatch `ctx_4e21aa` 가 잡혔어(Task `task_b310`).
그런데 75초가 지났는데 최신 agy 로그에서 `HandleUserInput called with text:` 를 세어 보니 0이야. 화면은 agy 환영 화면 그대로고 워크트리 변경도 없어.
이 Task 는 이전에 기동 실패가 없었어.

이제 어떻게 해야 해? 실행할 명령과 판단을 알려줘. 실행은 하지 마.
