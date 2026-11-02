# 성공 종료와 워커 정리 (i)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (종료)

- 게이트 통과와 리뷰 `pass`를 확인한다.
- **머지는 사람이 한다(자동 머지 금지).** 이유: 머지는 되돌리기 어려운 행위이고, 진행자(Sonnet)의 판단으로 사람의 최종 확인을 대체할 근거가 없다. 아래 어느 경로든 **머지 자체는 사람이 한다.**
- **구현 커밋은 (f)에서 이미 만들어졌다.** 여기서는 (g)에서 남긴 리뷰 리포트 커밋이 있는지만 확인한다.
- **커밋은 주체별로 나눈다.** 하네스 설정 / spec(설계자) / 구현(구현자) / 리뷰 리포트(리뷰어)를 각각 별도 커밋으로 남기고, 커밋 메시지에 어느 모델이 만들었는지 적는다. 나중에 `git log`만 보고 파이프라인의 어느 단계가 무엇을 만들었는지 가릴 수 있어야 한다.
- 사람이 직접 리뷰하는 단계(경로 B의 로컬 머지 전, 또는 경로 A의 PR 리뷰)에서 수정이 필요하면 그건 **추가 커밋**으로 처리한다. 이미 만든 커밋을 되돌리거나 amend할 필요 없다.

### 하위 워커 정리 — `worker_done` 전에 반드시

진행자 워커는 `worker_done` 뒤 설계 세션이 해제하므로, 정착한 하위 워커마다 재사용 / `worker-retain` / `worker-release` 중 하나를 정해 두고 보고한다. **진행자가 정하지 않으면 그 워커의 맥락을 아는 주체가 사라진다.** Orca는 진행자가 정착한 뒤에도 남은 하위 워커를 설계 세션의 Run에 넘기지만, 설계 세션은 그 워커가 무엇을 하던 중인지 모른다.

relay의 세 갈래 출구에 이를 대응시키면 이렇게 된다:

| 출구 | 구현 워커 (agy) | 리뷰 워커 (codex) |
|---|---|---|
| 성공 종료 (i) | `worker-release` + 터미널 close + `trustedWorkspaces` 해제 | `worker-release` |
| 수정 라운드 (g의 `BLOCKER`/`MAJOR`) | **재사용** — 닫지 않는다. 같은 handle로 새 dispatch를 건다 | `worker-release`. 다음 리뷰 라운드는 새 워커로 띄운다 — 이전 리뷰의 맥락에 끌려가지 않게 |
| `태스크를 중단한다` 답 (h) | `worker-retain` — 증거를 남긴다 | `worker-retain` |

성공 종료에서만 구현 워커를 해제한다:

구현 터미널은 (d)에서 직접 만든 것이라 release 가 닫지 않는다(state `retained` / reason `external_terminal` 로 남는다). `terminal show` 로 확인한 뒤 `terminal close` 로 닫는다.

- **`release`가 불확실하면 release의 recovery receipt를 따른다.** 위의 `terminal close`는 release의 대체가 아니라, release가 **성공한 뒤** 우리가 직접 만든 터미널을 만든 쪽이 정리하는 것이다.
  (**미검증**: Orca 가이드상 미리 존재하던 터미널은 release 후 `retained`로 남는다고 읽히지만 실측 전이다. 확인되면 이 주석을 고친다.)
- **산출물은 release 뒤에도 `worker-read`로 읽을 수 있으니 워커는 바로 release한다.**

**그리고 `trustedWorkspaces`에서 그 워크트리 경로를 지운다.** (d) 2번이 추가한 항목이고, 지우는 단계가 없으면 단조 증가한다.
워크트리 경로는 태스크명으로 재사용되므로,
죽은 항목이 남아 있으면 **미래의 다른 워크트리를 미리 신뢰하게 만든다.**

```bash
python "$RELAY/scripts/relay_cli.py" trust remove "<worktree path>"   # removed: / not present:
```

이미 남아 버린 죽은 항목은 `trust prune`(기본 dry-run, `--apply`로 삭제)이 `~/orca/workspaces/` 아래 항목만 골라 정리한다. 사용자가 직접 넣은 항목은 건드리지 않는다.

### 경로 A — 리뷰어가 따로 있는 저장소: PR

GitHub 리모트가 있고 다른 사람이 머지를 승인하는 경우:

```bash
git -C <worktree> push -u origin HEAD
gh pr create --head <branch> --base main \
  --title "T-NNN: <제목>" \
  --body "spec: .ai/specs/T-NNN-<슬러그>.md
review: .ai/reviews/T-NNN.rN.json
gate: <실행한 게이트 명령> — 통과"
```

### 경로 B — 저장소 오너가 직접 머지: 로컬 머지

오너 단독 저장소에서는 PR이 불필요한 왕복이다. 이때 진행자 워커는 **브랜치와 커밋까지만** 만들고 멈춘다.

```bash
# 진행자 워커는 여기까지만 한다: 브랜치명과 커밋 목록을 보고 파일에 적는다
git -C <worktree> log --oneline <base>..HEAD

# 아래는 사람이 실행한다 — 진행자 워커도 설계 세션도 대신 하지 않는다
git -C <repo> merge --no-ff <branch> -m "Merge branch '<branch>'"
```

`--no-ff`를 쓰는 이유: 머지 커밋이 남아야 한 태스크의 커밋 묶음이 이력에서 하나의 단위로 보인다. fast-forward하면 파이프라인 산출물이 main의 다른 커밋들 사이에 흩어진다.

**머지 후 게이트를 한 번 더 돌린다.** 브랜치에서 통과했어도 main과 합쳐진 뒤 깨질 수 있다.
단 **의존성 매니페스트나 lockfile이 바뀐 머지였다면 먼저 의존성을 동기화한다** (`bun install` 등). 안 하면 갱신된 매니페스트와 낡은 `node_modules`가 어긋나 실재하지 않는 오류가 나온다 — (f)의 3번 참조.

### 공통

- 리모트가 없으면 브랜치만 남기고 보고 파일에 브랜치명을 적는다.
- 어느 경로든 **진행자 워커는 머지하지 않고 `worker_done`으로 끝낸다.**

### 보고 — `worker_done`

진행자 워커의 끝은 세션 종료가 아니라 **보고**다. 설계 세션은 이 보고만 보고 다음 태스크로 넘어간다 — (b) 감독 루프 4).

1. **보고 파일을 쓴다** — `~/.relay/reports/<run_id>/T-NNN.md`. 워크트리 밖이라 커밋되지 않는다. 설계 세션이 이 파일에서 워크트리·`<base>`·브랜치를 읽어 확인한다.

   ```
   run: <run_id>
   task: T-NNN (<task_id>)
   outcome: succeeded | failed
   worktree: <worktree 경로>
   base: <base SHA>
   branch: <브랜치>
   pr: <PR URL | 없음 (경로 B)>
   review: <worktree>/.ai/reviews/T-NNN.rN.json (<verdict>)
   commits:
   <git -C <worktree> log --oneline <base>..HEAD 출력>
   retained: <worker-retain 한 하위 dispatch ID | 없음>
   warnings: <doctor WARN, 미검증 버전 | 없음>
   blocker: <중단 사유와 ask 메시지 ID | 없음>
   ```

2. **preamble의 `worker_done` 명령을 그대로 쓴다.** relay가 정하는 값:
   - `--outcome succeeded` — 성공 종료(i)를 마쳤을 때. `태스크를 중단한다` 답이나 기동 실패로 멈췄으면 `--outcome failed`. 실패를 `--body` 산문에만 적지 않는다.
   - `--body` — 세 문장: 무엇을 했는가(구현·리뷰 라운드 수), 무엇을 찾았는가(리뷰 verdict, 기각한 지적), 무엇이 남았는가(사람의 머지, PR 리뷰, 블로커).
   - `--report-path` — 1의 보고 파일.
3. 보낸 뒤에는 멈춘다. 진행자 워커 자신의 해제는 설계 세션이 한다.
