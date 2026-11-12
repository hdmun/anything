# PR 과 워커 출구 (i)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (종료)

- 모든 태스크의 게이트 통과와 리뷰 `pass`를 확인한다. PR 은 구현 이슈마다 하나다(ADR 0007).
- 기동 줄에 `일괄 진행:` 이 없으면 머지는 사람이 한다(자동 머지 금지). 있으면 PR 을 연 뒤 `references/merge.md` 로 간다. 이유: 머지는 되돌리기 어려운 행위이고, 진행자의 판단으로 사람의 최종 확인을 대체할 근거가 없다.
- **구현 커밋은 (f)에서 이미 만들어졌다.** 여기서는 (g)에서 남긴 리뷰 리포트 커밋이 태스크마다 있는지만 확인한다.
- **커밋은 주체별로 나눈다.** spec 스냅숏(진행자) / 구현(구현자) / 리뷰 리포트(리뷰어)를 각각 별도 커밋으로 남기고, 커밋 메시지에 어느 모델이 만들었는지 적는다. 나중에 `git log`만 보고 파이프라인의 어느 단계가 무엇을 만들었는지 가릴 수 있어야 한다.
- 사람이 PR 리뷰에서 수정이 필요하면 그건 **추가 커밋**으로 처리한다. 이미 만든 커밋을 되돌리거나 amend할 필요 없다.

### 워커 출구 — 세 줄

워커는 `worker_done` 뒤 스스로 닫힌다(Orca 1.4.247, ADR 0010). relay 가 정하는 것은 출구마다 이것뿐이다.

| 출구 | 구현 워커 (agy) | 리뷰 워커 (codex) |
|---|---|---|
| 성공 (리뷰 `pass`) | 할 일 없음 | 할 일 없음 |
| 수정 라운드 (g의 `fix_round`) | 구현 dispatch 에 `send` — 다시 열린다 | 할 일 없음. 다음 리뷰 라운드는 새 워커 |
| 멈춤 보고 (h) | `worker-keep-open` — 증거를 남긴다 | `worker-keep-open` |

멈출 때 워커를 남기는 이유: 무응답이나 예상 밖 프롬프트는 사람이 터미널 화면을 직접 봐야 원인을 알 수 있다. 닫히면 증거가 사라진다.

### `trustedWorkspaces` 정리 — PR 을 열 때 한 번

`worker-start --agent antigravity` 가 agy 를 띄울 때 Orca 가 이슈 워크트리를 `trustedWorkspaces` 에 추가하고((d) 1), 지우지 않는다. 워크트리 경로는 이름으로 재사용되므로, 죽은 항목이 남아 있으면 **미래의 다른 워크트리를 미리 신뢰하게 만든다.**

```bash
python "$RELAY/scripts/relay_cli.py" trust remove "<worktree path>"   # removed: / not present:
```

이미 남아 버린 죽은 항목은 `trust prune`(기본 dry-run, `--apply`로 삭제)이 `~/orca/workspaces/` 아래 항목만 골라 정리한다. 사용자가 직접 넣은 항목은 건드리지 않는다.

### 경로 A — GitHub: PR

GitHub 리모트가 있고 트래커가 GitHub 인 저장소. 제목은 **부모 이슈 제목**(하위 이슈가 없으면 이슈 제목)이다.

진행자는 git push나 gh 명령을 직접 부르지 않는다. 그 앞에 유출 검사가 있다(`publish`).

```bash
python "$RELAY/scripts/relay_cli.py" publish push --worktree <worktree>
python "$RELAY/scripts/relay_cli.py" publish pr --worktree <worktree> --title "<부모 이슈 제목>" --body-file <본문 파일>
```

- 결과 처리: `stop` 이면 멈춤 보고 — (h). `exists` 면 PR 을 새로 만들지 않았다는 것을 보고에 적는다(재개 때 생긴다). 일괄 진행이면 `created`·`exists` 모두 `references/merge.md` 로 간다(재개 때 `exists` 면 PR 을 새로 만들지 않고 머지 단계부터 다시 한다). 일반 relay 면 보고하고 끝난다.

본문:

```
Closes #<부모>
Closes #<하위 1>
Closes #<하위 2>

spec: .ai/specs/I-<n>-<슬러그>.md (태스크마다)
review: .ai/reviews/I-<n>.rN.json (태스크마다 마지막 리뷰)
gate: <실행한 게이트 명령> — 통과
warnings: <doctor WARN, 미검증 버전 | 없음>

사람이 할 일:
- 머지 전: 없음
- 머지 뒤:
  - [ ] <이슈의 항목 그대로>

기각한 지적:
- I-<n> j<N> (<dismiss|accept>): <판정 파일의 instruction>

남은 MINOR:
- I-<n> <file>:<line> <summary>
```

- 체크하는 정본은 이슈 본문이고 PR 본문은 읽기용 사본이다. 구현 이슈(하위 이슈가 있으면 부모, 없으면 이슈 자체)의 절에서 `머지 전:`·`머지 뒤:` 줄과 항목을 그대로 옮긴다.
- 「기각한 지적」은 `.ai/judgments/` 에서 `decision` 이 `dismiss`·`accept` 인 판정 파일의 `instruction` 을 모은 것이다. 없으면 이 절을 뺀다.
- 「남은 MINOR」 절: 태스크마다 마지막 리뷰 리포트의 `MINOR` 지적을 `- I-<n> <file>:<line> <summary>` 로 적는다. 없으면 절을 뺀다.

- 태스크마다 이슈의 지금 `updatedAt` 을 스냅숏 머리말의 값과 비교한다. 다르면 본문에 `태스크 도중 이슈가 바뀜: 반영 안 됨 — I-<n>` 줄을 더한다. 진행자는 바뀐 내용을 반영하지 않는다(ADR 0006).

### 경로 B — local-markdown: 브랜치와 커밋까지

트래커가 local-markdown 이거나 리모트가 없는 저장소. 진행자는 **브랜치와 커밋까지만** 만들고 멈춘다. 경로 A 의 본문 내용(이슈 경로, spec·review·gate·warnings)을 보고에 그대로 적는다.

```bash
# 진행자는 여기까지만 한다
git -C <worktree> log --oneline main..HEAD

# 아래는 사람이 실행한다 — 진행자가 대신 하지 않는다
git -C <repo> merge --no-ff <branch> -m "Merge branch '<branch>'"
```

`--no-ff`를 쓰는 이유: 머지 커밋이 남아야 구현 이슈 하나의 커밋 묶음이 이력에서 하나의 단위로 보인다.

**머지 후 게이트를 한 번 더 돌린다.** 브랜치에서 통과했어도 main과 합쳐진 뒤 깨질 수 있다.
단 **의존성 매니페스트나 lockfile이 바뀐 머지였다면 먼저 의존성을 동기화한다** (`bun install` 등). 안 하면 갱신된 매니페스트와 낡은 `node_modules`가 어긋나 실재하지 않는 오류가 나온다 — (f)의 3번 참조.

### 보고

일괄 진행이면 여기서 보고하지 않고 `references/merge.md` 로 간다.
PR 을 열었거나(경로 A) 브랜치를 남겼으면(경로 B) 사람에게 한 줄로 보고하고 끝난다: 구현 이슈, 태스크마다 결과(구현·리뷰 라운드 수, 기각한 지적), PR URL 또는 브랜치, 남은 일(사람의 PR 검토·머지).
