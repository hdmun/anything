# 일괄 진행 멈춤 보고

> 이 파일은 SKILL.md 의 단계 절차 중 일부다. SKILL.md 의 불변식과 함께 읽는다. (기동 줄에 `일괄 진행:` 이 있을 때만)

`references/stop.md` 「멈춤 보고」 3번의 코멘트를 이 형식으로 단다. 일반 형식에서 재개 줄을 바꾸고 한 줄을 더한 것이다:

```
relay 멈춤 — I-<n> <사유>: <사람이 정해야 할 것 한 줄>
근거: <worktree>/.relay/reviews/I-<n>.rN.json, <worktree>/.relay/judgments/I-<n>.jN.json, <spec 절>, <파일:줄>
워크트리: <worktree> / base: <base> / 브랜치: <branch>
남은 진행 목록: #<n>, #<n> (시작하지 않음)
재개: <고칠 것> 뒤 시작 명령 /relay:auto-merge <URL>
```

- `남은 진행 목록` 은 필드에서 이 이슈 뒤의 열린 이슈다. 없으면 `없음`.
- `<URL>` 은 보통 이 이슈다. main 깨짐이면 다음 열린 이슈다.
- 다음 handoff 실패로 **다음 이슈**에 다는 보고도 같은 형식이다. 이때 남은 진행 목록은 다음 이슈 뒤의 열린 이슈다.
- 머지 조건이 어긋난 채 재개 시: 사람은 PR 을 직접 머지하고 시작 명령을 다시 치거나, PR 을 닫고 이슈 워크트리를 지운 뒤 처음부터 한다.

유출 검사로 멈춘 경우의 보고는 `stop.md` 와 같고, 재개 줄의 두 길에서 `relay:start` 대신 시작 명령을 적는다.

- 오탐: `~/.relay/leak-rules.toml` 이나 저장소의 `.relay/leak-allow.toml`(사람이 main 에 커밋)을 고친 뒤 시작 명령 `/relay:auto-merge <URL>`.
- 진짜 값: 원인(예: 이슈 본문의 실제 값)을 고치고, 이슈 워크트리와 브랜치를 지운 뒤 시작 명령 `/relay:auto-merge <URL>`.
