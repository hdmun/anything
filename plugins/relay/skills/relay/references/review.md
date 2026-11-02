# 리뷰 결과 처리 (g)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (리뷰 분기)

리뷰어는 `.ai/reviews/T-NNN.rN.json`(`N`은 리뷰 라운드 번호, 1부터)을 쓰고 `worker_done`의 `--report-path`로 경로를 넘긴다.

**라운드마다 파일을 따로 남기는 이유는 (h)의 카운터 때문이다.** 진행 세션은 태스크마다 폐기되므로 라운드 수를 컨텍스트에 들고 있을 수 없다. 파일 개수가 곧 라운드 수이고, git에 남아 세션과 무관하게 유지된다.

`worker_done`을 받으면 **판정을 스크립트에 맡긴다.** 검증·심각도 분기·라운드 한도가 한 번에 나온다.

```bash
python "$RELAY/scripts/relay_cli.py" review-branch --task T-NNN --worktree <worktree> --base <base>
# {"action": "fix_round", "report": ".../T-NNN.r1.json", "review_rounds": 1, "impl_rounds": 1, "round": 2, "severities": ["MAJOR"]}
```

| `action` | 할 일 |
|---|---|
| `rewrite` | 리포트가 `references/review-schema.json`을 어겼다. `errors`를 리뷰어에게 그대로 보내 재작성을 요구한다 — 비용은 리뷰 1회 재실행뿐. **리포트를 커밋하지 않는다** |
| `success` | 리포트를 커밋하고 성공 종료 — (i). `MINOR`만 있어도 여기로 온다 (수정을 요구하지 않는다 — 핑퐁 방지) |
| `fix_round` | 리포트를 커밋하고 아래 「수정 라운드」. `round`가 다음 리뷰 라운드 번호다 |
| `escalate` | 리포트를 커밋하고 설계 세션(Opus)으로 — (h). `reason`을 게이트 질문에 적는다 |
| `human` | 리포트를 커밋하고 사람 호출, 태스크 중단 — (h) |

판정 규칙(심각도 우선순위, 반복 지적 비교, 라운드 한도)의 정본은 `scripts/relaylib/review.py`와 그 테스트다. 여기서 다시 계산하지 않는다.
**왜 이렇게 나누는가**: `SPEC_VIOLATION`은 명세를 쓴 주체만 옳고 그름을 가릴 수 있어 진행자가 판단하지 않는다. 같은 지적이 직전 라운드에 이어 또 나오면 구현자로는 못 고친다는 뜻이다. 라운드 한도는 비용 상한이다.

리뷰 리포트 커밋은 아래 형식을 따른다. 구현 커밋의 `Implemented-by:`와 짝이다.

```
review(T-NNN): rN <verdict>

Reviewed-by: codex/<리뷰 워커 codex 명령줄에 준 -m 값>
```

### 수정 라운드는 새 Task + 새 Dispatch로 만든다

**워커가 `worker_done`을 보내는 순간 그 Dispatch는 `completed`가 되고, `send --to dispatch:<id>`는 `dispatch_inactive`로 거부된다.** Orca가 *"its worker will never read that mailbox"* 라며 명시적으로 막는다. 실측으로 확인된 동작이다. 따라서 수정 지시를 기존 dispatch에 보내려는 시도는 반드시 실패한다.

```bash
orca orchestration task-create \
  --task-title "T-NNN 수정 라운드 N" \
  --parent <원래 task_id> \
  --spec "T-NNN 리뷰 지적 수정. 리뷰: .ai/reviews/T-NNN.rN.json / 원본 명세: .ai/specs/T-NNN-<슬러그>.md" --json

orca orchestration worker-show --dispatch <이전 dispatch_id> --json
orca terminal wait --terminal <agent_terminal_handle> --for tui-idle --timeout-ms 30000 --json   # 재사용 전 확인
orca orchestration worker-start --task <새 task_id> --terminal <agent_terminal_handle> --json
```

- **워커 터미널은 살아 있으므로 같은 handle을 재사용한다.** 세션 컨텍스트가 유지되어 배경을 다시 설명할 필요가 없다.
- **재사용 전에 `tui-idle`부터 통과시킨다.** `worker-start`는 안에서 같은 준비 대기를 하고, 실패하면 새 Task가 바로 `failed`가 된다.
  timeout이면 (d)4와 같이 화면을 `readiness`에 묻는다(`--command`는 그 터미널을 만들 때 준 값).
  - `recreate_terminal / header_scrolled_out`: 긴 세션으로 머리글이 Orca 꼬리 밖으로 밀려났다. 기다려도 돌아오지 않는다(실측 T-007: 3회 연속 timeout, 새 터미널은 즉시 통과).
    이전 Dispatch를 `worker-release` → 터미널 `close` → 결정의 `launch_command`로 새로 만들어 `tui-idle` → 새 handle로 `worker-start --terminal`.
    **맥락은 잃는다** — 수정 Task spec이 리뷰 파일과 원본 명세 경로를 담고 있으므로 그것으로 충분해야 한다.
    재생성 직후 첫 `worker-start`는 `agent_unconfigured`가 올 수 있다 — `startup`의 `wait_tui_idle`대로 `tui-idle`을 다시 걸고 재시도하면 통과한다(실측 2회).
  - **`/clear`로 머리글을 되살리지 않는다.** 실측(2026-10-11, agy 1.3.3): `/clear` 뒤 머리글이 다시 찍혀 `tui-idle`은 통과하지만, 대화 맥락도 지워진다(기억시킨 단어를 `UNKNOWN`으로 답함). 맥락을 지키려는 재사용의 목적이 사라지므로 새 터미널보다 나을 것이 없다. 보내야 한다면 Git Bash에서 `MSYS_NO_PATHCONV=1`을 붙인다.
- **`worker-start --terminal`로 재사용한다.** 정본이 정착 후 재사용에 지정한 경로이고, **cleanup 소유권이 새 Dispatch로 넘어가** 감독이 끊기지 않는다. `dispatch --inject`로 보내면 그 순간부터 비감독이 된다.
- `--terminal`은 `--model`/`--effort`와 함께 쓸 수 없다. 터미널이 이미 그 모델로 떠 있으므로 문제되지 않는다.
- `--parent`로 원래 태스크에 묶으면 수정 라운드가 DAG에 기록된다.
- **조치가 필요 없는 단순 안내**라면 Task를 만들지 말고 `orca terminal send --terminal <handle> --text "..." --enter` 로 직접 보낸다.

**구현 커밋은 (f)에서 이미 만들어져 있다.** 분기는 그 커밋을 만들지 여부가 아니라 다음 라운드를 열지를 정한다. 수정 라운드의 결과는 기존 커밋을 amend하지 않고 **새 커밋**으로 쌓는다.
