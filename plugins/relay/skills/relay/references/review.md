# 리뷰 결과 처리 (g)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (리뷰 분기)

리뷰어는 `.ai/reviews/T-NNN.rN.json`(`N`은 리뷰 라운드 번호, 1부터)을 쓰고 `worker_done`의 `--report-path`로 경로를 넘긴다.

**라운드마다 파일을 따로 남기는 이유는 (h)의 카운터 때문이다.** 진행자 워커는 태스크마다 새로 뜨고 해제되므로 라운드 수를 컨텍스트에 들고 있을 수 없다. 파일 개수가 곧 라운드 수이고, git에 남아 워커와 무관하게 유지된다.

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
| `escalate` | 리포트를 커밋하고 설계 세션에 `ask` — (h). `reason`이 질문의 사유다 |
| `human` | 리포트를 커밋하고 설계 세션에 `ask`(사람이 필요한 것) — (h) |

판정 규칙(심각도 우선순위, 반복 지적 비교, 라운드 한도)의 정본은 `scripts/relaylib/review.py`와 그 테스트다. 여기서 다시 계산하지 않는다.
**왜 이렇게 나누는가**: `SPEC_VIOLATION`은 명세를 쓴 주체만 옳고 그름을 가릴 수 있어 진행자가 판단하지 않는다. 같은 지적이 직전 라운드에 이어 또 나오면 구현자로는 못 고친다는 뜻이다. 라운드 한도는 비용 상한이다.

리뷰 리포트 커밋은 아래 형식을 따른다. 구현 커밋의 `Implemented-by:`와 짝이다.

```
review(T-NNN): rN <verdict>

Reviewed-by: codex/<리뷰 워커 영수증의 launch.effective.model>
```

### 수정 라운드는 새 Task + 새 Dispatch로 만든다

**워커가 `worker_done`을 보내면 그 Dispatch는 `completed`가 되고, `send --to dispatch:<id>`는 `dispatch_inactive`로 거부된다.** 수정 지시는 새 Task와 새 Dispatch로 보낸다 — Orca 가이드 `coordinator-loop` reference 「Reuse after settlement」.

1. `worker-show --dispatch <이전 구현 dispatch_id>` 로 에이전트 터미널 handle 을 되찾는다
2. preamble SUB-DISPATCH의 `worker-start`로 같은 터미널에 새 Task를 건다. relay 값:
   - `--spec "T-NNN 수정 라운드 N. 리뷰: .ai/reviews/T-NNN.rN.json / 원본 명세: .ai/specs/T-NNN-<슬러그>.md / base: <base>"`
   - `--parent <이전 구현 task_id>`, `--worktree id:<wt>`, `--terminal <agent_terminal_handle>`
3. 영수증을 `implementer.md` 4대로 읽는다

- **워커 터미널은 살아 있으므로 같은 handle을 재사용한다.** 세션 컨텍스트가 유지되어 배경을 다시 설명할 필요가 없다. **cleanup 소유권이 새 Dispatch로 넘어가** 감독도 끊기지 않는다. `dispatch --inject`로 보내면 그 순간부터 비감독이 된다.
- `--terminal`은 `--model`/`--effort`와 함께 쓸 수 없다. 터미널이 이미 그 모델로 떠 있으므로 문제되지 않는다.
- 재사용이 기동 실패로 끝나면 그 터미널은 포기한다. 이전 Dispatch를 `worker-release`하고, `implementer.md` 3(예열)·4대로 **새 워커**를 `--agent antigravity`로 띄운다. **맥락은 잃는다** — 수정 Task spec이 리뷰 파일과 원본 명세 경로를 담고 있으므로 그것으로 충분해야 한다.
- `--parent`로 원래 태스크에 묶으면 수정 라운드가 DAG에 기록된다.
- **조치가 필요 없는 단순 안내**라면 Task를 만들지 말고 `terminal send --text "..." --enter` 로 직접 보낸다.

**구현 커밋은 (f)에서 이미 만들어져 있다.** 분기는 그 커밋을 만들지 여부가 아니라 다음 라운드를 열지를 정한다. 수정 라운드의 결과는 기존 커밋을 amend하지 않고 **새 커밋**으로 쌓는다.
