# 멈춤 보고 (h)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (멈춤)

진행자 세션은 Run 을 소유한 최상위 코디네이터라 물어볼 위 세션이 없다(ADR 0005). 혼자 판단할 수 없으면 **멈춤 보고를 남기고 끝난다**(ADR 0008). 다음 결정을 어디서 할지는 사람이 정하고, 사람의 결정은 구현 이슈 본문으로만 전해진다. 재개는 같은 이슈로 다시 `relay:handoff` 한다.

| 트리거 | 판정 |
|---|---|
| `review-branch`의 `escalate` — `spec_violation`, `repeated_finding`, `review_round_limit` | (g) |
| `review-branch`의 `human` — `total_round_limit` | (g) |
| 워커의 `escalation`(`stopReason`이면 다시 지시한 뒤 두 번째), spec 해석이 필요한 `question` | (e) |
| `doctor`·`handoff-check` `FAIL`, 스냅숏 `author_not_trusted`, 빨간 기준선 | (c) |
| Orca의 기동 실패 circuit-break | 아래 「시도와 라운드」 |
| 영수증의 `agent_prompt_blocked`·`outcome_unknown`, `commit-guard` 실패, 그 밖에 문서가 사람을 부르라는 곳 | (d)(f), SKILL.md 불변식 |

`agent_prompt_blocked` 는 끝나지 않고 사람이 그 터미널에서 처리하기를 기다린다(SKILL.md 불변식). 사람이 처리했다고 이 세션에 말하면 막힌 단계부터 이어 간다.

### 멈춤 보고의 형식

1. **증거를 커밋으로 남긴다.** 리뷰 리포트는 (g)대로 커밋한다. 구현 커밋은 (f)에서 이미 있다.
2. 정착한 워커는 출구 표대로 `worker-keep-open` 으로 남긴다 — (i).
3. **구현 이슈에 코멘트를 단다**(경로 B 면 이슈 파일 끝에 덧붙이지 않고 사람에게만 보고한다). 첫 줄이 사람이 정해야 할 것 한 줄이다:

   ```
   relay 멈춤 — I-<n> <사유>: <사람이 정해야 할 것 한 줄>
   근거: <worktree>/.ai/reviews/I-<n>.rN.json, <spec 절>, <파일:줄>
   워크트리: <worktree> / base: <base> / 브랜치: <branch>
   재개: 이슈를 고친 뒤 같은 이슈로 relay:handoff
   ```

4. 이 세션에도 같은 내용을 남기고 끝난다. 끝난 태스크의 커밋은 브랜치에 남는다(ADR 0007).

### 시도와 라운드를 구분한다

용어의 정본은 `CONTEXT.md`다. 셋을 섞으면 예산이 엉뚱하게 깎인다.

| 용어 | 뜻 | 세는 법 (재개해도 남는 곳) |
|---|---|---|
| **기동 실패** | 워커가 태스크 프롬프트를 받기 전에 실패한 것. Orca가 영수증으로 보고한 실패(`agent_readiness`, `agent_prompt_blocked` 등)와 `outcome_unknown`을 모두 포함한다. **라운드가 아니다** | Orca Task의 실패 이력 |
| **구현 라운드** | 게이트를 통과해 커밋으로 남은 구현 한 번 | `git log <base>..HEAD`의 `Implemented-by:` 트레일러 커밋 수 — **트레일러가 빠진 커밋은 세지 못한다** |
| **리뷰 라운드** | 리뷰 리포트 하나 | `.ai/reviews/I-<n>.r*.json` 파일 개수 |
| **총 라운드** | 구현 라운드 + 리뷰 라운드 | 위 둘의 합 (`review-branch`가 센다) |

- **기동 실패의 끝은 Orca의 3회 circuit-break다.** 그 전까지는 Orca 가이드 `recovery-and-cleanup`의 복구 절차대로 같은 Task에 다시 띄운다. breaker가 걸리면 멈춤 보고(ADR 0009).
- 기동 실패는 환경 문제이고 구현자의 실력과 무관하므로 라운드 예산을 깎지 않는다.
