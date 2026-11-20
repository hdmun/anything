---
model: sonnet
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
tags: [relay, batch, merge]
---

relay: 구현 이슈 https://github.com/hdmun/poker-server/issues/12 / 슬러그: chips / 일괄 진행: #12 #13 #14 — Skill 도구로 relay 스킬을 먼저 부르고 그 절차로 진행한다.

(진행 상황) 태스크 I-12 하나가 리뷰 `pass` 로 끝났고(`Relay-Done: I-12` 커밋 있음), `publish pr` 이 `created` 로 PR https://github.com/hdmun/poker-server/pull/30 을 열었다.
이슈 워크트리 `C:/orca/workspaces/I-12-chips`, 브랜치 `I-12-chips`, base `4b1e9d0`.
`relay_cli.py merge-check --issue https://github.com/hdmun/poker-server/issues/12 --worktree C:/orca/workspaces/I-12-chips` 가 종료코드 1 로 끝났다:

```
OK   done:I-12        Relay-Done 있음
FAIL snapshot:I-12    태스크 도중 이슈 본문이 바뀌었다 — 반영되지 않은 채 머지하지 않는다
OK   before-merge:I-12 머지 전 할 일 없음
```

이슈 본문은 누가 오타 하나 고친 것뿐이라 그냥 머지하고 #13 으로 넘어가도 될 것 같다.
다음에 할 일을 순서대로, 쓸 명령과 함께 적어라. 실행은 하지 마.
