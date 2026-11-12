# 판정과 멈춤 보고 (h)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (판정·멈춤)

진행자는 spec 을 스스로 해석하지 않는다. spec 판단이 필요한 셋은 **판정 서브에이전트**에 맡기고, 그 밖에 혼자 풀 수 없는 것은 **멈춤 보고**를 남기고 끝난다(ADR 0005·0008). 물어볼 위 세션은 없다.

| 트리거 | 처리 |
|---|---|
| `review-branch`의 `escalate` — `spec_violation`, `repeated_finding` | 판정 |
| 워커의 spec 해석 `question` | 판정 |
| 워커의 `escalation`(`stopReason`이면 다시 지시한 뒤 두 번째), spec 해석이 아닌 질문 중 진행자가 답할 수 없는 것 | 멈춤 보고 |
| `doctor`·`handoff-check` `FAIL`, 스냅숏 `author_not_trusted`, 빨간 기준선 | 멈춤 보고 — (c) |
| `publish`의 `stop` | 멈춤 보고 (브랜치·워크트리는 남긴다) |
| 머지 단계: `merge-check` FAIL, main 과 충돌, 합친 결과 게이트 실패, `gh pr merge` 실패(셋 다 PR 은 연 채), main 깨짐(닫힌 이슈에 코멘트), 다음 handoff 실패(다음 이슈에 코멘트, 자기 워크트리를 남김) | 멈춤 보고 — `references/merge.md` |
| Orca의 기동 실패 circuit-break, 영수증의 `outcome_unknown`, `commit-guard` 실패, 그 밖에 문서가 사람을 부르라는 곳 | 멈춤 보고 — (d)(f), SKILL.md 불변식 |

일괄 진행에서 멈추면 진행 목록 전체가 멈춘다. 멈춘 진행자 세션은 다음 이슈를 handoff 하지 않고, 자기 워크트리를 지우지 않는다.

`agent_prompt_blocked` 는 끝나지 않고 사람이 그 터미널에서 처리하기를 기다린다(SKILL.md 불변식). 사람이 처리했다고 이 세션에 말하면 막힌 단계부터 이어 간다.

## 판정 서브에이전트

### 1. 띄운다

```bash
python "$RELAY/scripts/relay_cli.py" model judge
# {"action": "launch", "agent": "subagent", "model": "opus", "effort": "high", "source": "default"}
```

- `launch` 의 `model`·`effort` 를 **Agent 도구**의 `model`·`effort` 에 그대로 준다. `human / judge_model_invalid` 면 설정의 `judge.model` 이 Agent 도구 별칭이 아니다 — 멈춤 보고.
- 프롬프트는 **경로를 넘긴다.** 본문으로 넘기는 것은 워커 `question` 텍스트뿐이다.

  ```
  relay 판정: <사유> / I-<n>
  워크트리: <worktree> / base: <base>
  spec: <worktree>/.ai/specs/I-<n>-<슬러그>.md
  리뷰: <worktree>/.ai/reviews/I-<n>.rN.json   (repeated_finding 이면 직전 리포트도)
  질문: <워커 question 원문>                     (question 일 때만)
  형식: <$RELAY>/skills/relay/references/judgment-schema.json 의 JSON 하나만 돌려준다.
  규칙: 읽기만 한다 — 파일 수정·커밋·워커 메시지 금지. diff 는 git -C <worktree> diff <base>..HEAD 로 직접 본다.
        판정은 spec 안에서만 한다. spec 이 틀렸거나, spec 에 없는 새 결정이 필요하거나, 태스크를 쪼개야 하면 stop.
  ```

### 2. 검증한다

받은 JSON 을 파일로 쓰고 검증한다 — `spec_violation`·`repeated_finding` 은 `.ai/judgments/I-<n>.jN.json`(N 은 그 태스크의 판정 번호, 1부터), `question` 은 워크트리 밖 임시 파일.

```bash
python "$RELAY/scripts/relay_cli.py" judgment validate <파일> --reason <사유> ; echo "exit=$?"
```

- 종료코드 1이면 stderr 오류를 붙여 **한 번만** 다시 부른다. 또 실패하면 멈춤 보고.

### 3. 판정대로 한다

| `reason` | `decision` | 진행자가 할 일 |
|---|---|---|
| `spec_violation` | `fix_impl` | 판정 기록 커밋 → 수정 라운드 — (g). `instruction` 을 수정 지시에 넣는다 |
| `spec_violation` | `dismiss` | 판정 기록 커밋(`Relay-Done`) → 태스크 성공, 다음 태스크 |
| `repeated_finding` | `another_round` | 판정 기록 커밋 → 수정 라운드 — (g). `instruction` 을 넣는다 |
| `repeated_finding` | `accept` | 판정 기록 커밋(`Relay-Done`) → 태스크 성공, 다음 태스크 |
| `question` | `answer` | 커밋하지 않는다. `instruction` 을 근거(`rationale`)째 워커에 `reply` 한다 — 구현자가 같은 워크트리에서 작업 중이다 |
| 어느 사유든 | `stop` | (`question` 이 아니면 판정 기록 커밋 후) 멈춤 보고. 첫 줄은 `stop_summary` |

판정 기록 커밋은 결과와 상관없이 남긴다(`stop` 포함 — 증거다). 형식:

```
judge(I-<n>): jN <decision>

Judged-by: claude/<Agent 도구가 띄운 모델>
Relay-Done: I-<n>        ← dismiss·accept 일 때만
```

- `Relay-Done` 이 있으면 재개 때 `resume` 이 그 태스크를 건너뛴다(ADR 0010).
- `Judged-by:` 는 귀속 트레일러다 — `commit-guard` 가 진행자 커밋으로 받는다. 기각 근거(`dismiss`·`accept` 의 `instruction`)는 PR 본문에 모은다 — (i).

## 멈춤 보고

1. **증거를 커밋으로 남긴다.** 리뷰 리포트는 (g)대로, 판정 기록은 위대로 커밋한다. 구현 커밋은 (f)에서 이미 있다.
2. 정착한 워커는 출구 표대로 `worker-keep-open` 으로 남긴다 — (i).
3. **구현 이슈에 코멘트를 단다**(트래커가 local-markdown 이면 이슈 파일은 고치지 않고 사람에게만 보고한다).
   코멘트는 `python "$RELAY/scripts/relay_cli.py" publish comment --worktree <worktree> --issue <이슈 URL> --body-file <파일>` 로 단다.
   그 명령이 `stop/leak` 이면 `python "$RELAY/scripts/relay_cli.py" publish comment --worktree <worktree> --issue <이슈 URL> --leak-notice` 로 고정 문장만 단다. 그것도 실패하면 세션 출력에만 남긴다.

   첫 줄이 사람이 정해야 할 것 한 줄이다:

   ```
   relay 멈춤 — I-<n> <사유>: <사람이 정해야 할 것 한 줄>
   근거: <worktree>/.ai/reviews/I-<n>.rN.json, <worktree>/.ai/judgments/I-<n>.jN.json, <spec 절>, <파일:줄>
   워크트리: <worktree> / base: <base> / 브랜치: <branch>
   재개: 이슈를 고친 뒤 같은 이슈로 relay:handoff
   ```

   기동 줄에 `일괄 진행:` 이 있으면 재개 줄을 바꾸고 한 줄을 더한다:

   ```
   relay 멈춤 — I-<n> <사유>: <사람이 정해야 할 것 한 줄>
   근거: <worktree>/.ai/reviews/I-<n>.rN.json, <worktree>/.ai/judgments/I-<n>.jN.json, <spec 절>, <파일:줄>
   워크트리: <worktree> / base: <base> / 브랜치: <branch>
   남은 진행 목록: #<n>, #<n> (시작하지 않음)
   재개: <고칠 것> 뒤 시작 명령 /relay:batch <URL>
   ```

   - `남은 진행 목록` 은 필드에서 이 이슈 뒤의 열린 이슈다. 없으면 `없음`.
   - `<URL>` 은 보통 이 이슈다. main 깨짐이면 다음 열린 이슈다.
   - 다음 handoff 실패로 **다음 이슈**에 다는 보고도 같은 형식이다. 이때 남은 진행 목록은 다음 이슈 뒤의 열린 이슈다.
   - 머지 조건이 어긋난 채 재개 시: 사람은 PR 을 직접 머지하고 시작 명령을 다시 치거나, PR 을 닫고 이슈 워크트리를 지운 뒤 처음부터 한다.

   유출 검사로 멈춘 경우(푸시·PR 의 `stop/leak`·`allowlist_changed`)의 보고: 첫 줄에 `파일:줄`·규칙 id 만 적고 값은 적지 않는다. 로그 경로(`.ai/leak/…`)를 적는다. 재개 줄에는 두 길을 적는다.
   - 오탐: `~/.relay/leak-rules.toml` 이나 저장소의 `.ai/leak-allow.toml`(사람이 main 에 커밋)을 고친 뒤 같은 이슈로 `relay:handoff`(일괄 진행이면 시작 명령 `/relay:batch <URL>`).
   - 진짜 값: 원인(예: 이슈 본문의 실제 값)을 고치고, 이슈 워크트리와 브랜치를 지운 뒤 같은 이슈로 `relay:handoff`(일괄 진행이면 시작 명령 `/relay:batch <URL>`).
   - 진행자는 커밋 이력을 고치지 않는다.

4. 이 세션에도 같은 내용을 남기고 끝난다. PR 은 열지 않는다. 끝난 태스크의 커밋은 브랜치에 남는다(ADR 0007).

### 시도와 라운드를 구분한다

용어의 정본은 `CONTEXT.md`다.

| 용어 | 뜻 | 세는 법 (재개해도 남는 곳) |
|---|---|---|
| **기동 실패** | 워커가 태스크 프롬프트를 받기 전에 실패한 것. Orca가 영수증으로 보고한 실패(`agent_readiness`, `agent_prompt_blocked` 등)와 `outcome_unknown`을 모두 포함한다. **라운드가 아니다** | Orca Task의 실패 이력 |
| **구현 라운드** | 게이트를 통과해 커밋으로 남은 구현 한 번 | `git log <base>..HEAD`의 `Implemented-by:` 트레일러 커밋 수 — **트레일러가 빠진 커밋은 세지 못한다** |
| **리뷰 라운드** | 리뷰 리포트 하나 | `.ai/reviews/I-<n>.r*.json` 파일 개수 |
| **총 라운드** | 구현 라운드 + 리뷰 라운드 | 위 둘의 합 (기록용, 한도 없음) |

- **기동 실패의 끝은 Orca의 3회 circuit-break다.** 그 전까지는 Orca 가이드 `recovery-and-cleanup`의 복구 절차대로 같은 Task에 다시 띄운다. breaker가 걸리면 멈춤 보고(ADR 0009).
- 기동 실패는 환경 문제이고 구현자의 실력과 무관하므로 라운드로 세지 않는다.
