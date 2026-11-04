# 리뷰 결과 처리 (g)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (리뷰 분기)

리뷰어는 `.ai/reviews/I-<n>.rN.json`(`N`은 리뷰 라운드 번호, 1부터)을 쓰고 `worker_done`의 `--report-path`로 경로를 넘긴다.

**라운드마다 파일을 따로 남기는 이유는 (h)의 카운터 때문이다.** 라운드 수를 진행자의 컨텍스트에 들고 있지 않는다 — 재개한 진행자도 같은 수를 센다. 파일 개수가 곧 라운드 수이고, git에 남아 세션과 무관하게 유지된다.

`worker_done`을 받으면 **판정을 스크립트에 맡긴다.** 검증·심각도 분기·라운드 한도가 한 번에 나온다.

```bash
python "$RELAY/scripts/relay_cli.py" review-branch --task I-<n> --worktree <worktree> --base <base>
# {"action": "fix_round", "report": ".../I-<n>.r1.json", "review_rounds": 1, "impl_rounds": 1, "round": 2, "severities": ["MAJOR"]}
```

| `action` | 할 일 |
|---|---|
| `rewrite` | 리포트가 `references/review-schema.json`을 어겼다. `errors`를 리뷰어에게 그대로 보내 재작성을 요구한다 — 비용은 리뷰 1회 재실행뿐. **리포트를 커밋하지 않는다** |
| `success` | 리포트를 커밋하고 이 태스크를 끝낸다 — 다음 태스크로 (c), 모두 끝났으면 PR (i). `MINOR`만 있어도 여기로 온다 (수정을 요구하지 않는다 — 핑퐁 방지) |
| `fix_round` | 리포트를 커밋하고 아래 「수정 라운드」. `round`가 다음 리뷰 라운드 번호다 |
| `escalate` | 리포트를 커밋하고 멈춤 보고 — (h). `reason`이 보고의 사유다 |
| `human` | 리포트를 커밋하고 멈춤 보고(사람이 필요한 것) — (h) |

판정 규칙(심각도 우선순위, 반복 지적 비교, 라운드 한도)의 정본은 `scripts/relaylib/review.py`와 그 테스트다. 여기서 다시 계산하지 않는다.
**왜 이렇게 나누는가**: `SPEC_VIOLATION`은 명세를 쓴 주체만 옳고 그름을 가릴 수 있어 진행자가 판단하지 않는다. 같은 지적이 직전 라운드에 이어 또 나오면 구현자로는 못 고친다는 뜻이다. 라운드 한도는 비용 상한이다.

리뷰 리포트 커밋은 아래 형식을 따른다. 구현 커밋의 `Implemented-by:`와 짝이다.

```
review(I-<n>): rN <verdict>

Reviewed-by: codex/<리뷰 워커 영수증의 launch.effective.model>
```

### 수정 라운드는 구현 dispatch 에 `send` 한다

워커는 `worker_done` 뒤 스스로 닫히고, 닫힌 워커에 `send` 하면 Orca 가 후속 Task 로 다시 연다(Orca 1.4.247, ADR 0010). 명령은 Orca 가이드를 따른다.

1. 이전 **구현** dispatch 에 `send` 한다. 본문: `I-<n> 수정 라운드 N. 리뷰: .ai/reviews/I-<n>.rN.json / 원본 명세: .ai/specs/I-<n>-<슬러그>.md / base: <base>`
2. 영수증을 `implementer.md` 3대로 읽는다. 다시 연 워커는 이전 세션 컨텍스트를 이어 가므로 배경을 다시 설명할 필요가 없다.

- 다시 열기가 기동 실패로 끝나면 `implementer.md` 2(예열)·3대로 **새 워커**를 `--agent antigravity`로 띄운다. **맥락은 잃는다** — 수정 지시가 리뷰 파일과 원본 명세 경로를 담고 있으므로 그것으로 충분해야 한다.
- **리뷰어는 라운드마다 새 워커**로 띄운다(`reviewer.md`) — 이전 리뷰의 맥락에 끌려가지 않게. 리뷰 dispatch 에는 `send` 하지 않는다.

**구현 커밋은 (f)에서 이미 만들어져 있다.** 분기는 그 커밋을 만들지 여부가 아니라 다음 라운드를 열지를 정한다. 수정 라운드의 결과는 기존 커밋을 amend하지 않고 **새 커밋**으로 쌓는다.
