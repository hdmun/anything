# 진행자 워커 시작 (c) 0~3

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (진행자 워커 시작)

## (c) 진행자 워커 절차

0. **preamble을 확인한다.** 프롬프트에 Orca preamble(`You are a dispatched worker`, Task ID·Dispatch ID가 박힌 `worker_done` 명령, `=== TASK ===` 블록)이 있어야 진행자 워커다. 없으면 설계 세션이다 — `references/design.md`로 간다.
   - **preamble이 정본이다.** `worker_done`·`ask`·`heartbeat`·`check` 명령은 preamble에 적힌 것을 그대로 쓴다. handle·Task ID·Dispatch ID를 다시 조립하지 않는다.
   - `=== TASK ===` 첫머리 `relay 진행자: Run <run_id> / I-<n>`에서 Run ID와 태스크 ID를, `이슈:`·`슬러그:` 뒤에서 구현 이슈와 슬러그를 읽는다. 다음 태스크는 설계 세션이 고른다 — `task-list`로 꺼내지 않는다.
   - `=== SUB-DISPATCH ===` 절이 없으면 하위 워커를 띄울 수 없다(Orca 워커 중첩 깊이). 사람이 필요한 것으로 `ask` 한다 — (h).
1. **Skill 도구로 Orca 스킬 `orchestration` 과 `orca-cli` 를 불러 Orca 가이드를 먼저 읽는다.**
   진행자 워커는 dispatched worker이면서 구현자·리뷰어의 코디네이터다. 가이드의 워커 의무(heartbeat·`ask`·`worker_done`)와 감독 루프를 모두 따른다. 하위 워커는 preamble의 SUB-DISPATCH대로 이 Dispatch의 Run에 띄운다 — `run-create`·`run-use`를 하지 않는다.
   relay 문서는 orca 명령 문법을 적지 않는다 — 동사 이름과 relay가 정한 값만 적는다. **충돌하면 Orca 가이드가 옳고, 이 스킬을 고친다.** Orca 기본과 일부러 다르게 하는 것은 SKILL.md 「Orca 기본과 다른 점」에만 있다.
   relay가 더하는 것은 명령 사용법이 아니라 그 위의 정책이다 — 역할 분리, 심각도 라우팅, 태스크마다 새 진행자 워커. **relay 정책은 `relay_cli.py`가 판정한다**(ADR 0001). 판정 규칙을 이 문서에서 다시 계산하지 않는다.
2. **머신을 점검한다** — `python "$RELAY/scripts/relay_cli.py" doctor`. 설계 세션이 이미 돌렸어도 다시 한다. 셸 명령이라 비용이 0이고, 워커가 읽은 플러그인 사본은 설계 세션과 다를 수 있다.
   - `FAIL`(종료코드 1)이면 시작하지 않는다. 출력의 `→` 줄(고치는 방법)을 사람이 필요한 것으로 `ask` 한다 — (h). 답이 `사람이 해결했다`면 doctor부터 다시 한다.
   - 특히 `FAIL plugin`은 **이 워커가 읽은 SKILL.md가 설치본보다 낡았다**는 뜻이다. references Read가 "파일 없음"으로 실패하는 것도 같은 신호다. 낡은 절차로 진행하면 이미 고친 문제를 다시 밟는다.
   - `FAIL models`는 모델 설정 파일(`~/.relay/models.json`, `.ai/relay-models.json`)이 잘못됐다는 뜻이다. 설정 파일이 없으면 `OK`다 — 기본 동작.
   - `WARN`은 보고 파일에 적고 진행한다 — (i). 미검증 버전(`WARN version:*`)의 smoke는 설계 세션이 사람과 정한다.
3. **spec 스냅숏을 뜬다** — 워크트리를 만든 직후((d) 1), 워커를 띄우기 전에 한다. 정본은 구현 이슈이고, 스냅숏은 태스크 시작 시점의 고정 사본이다(ADR 0006).

   ```bash
   python "$RELAY/scripts/relay_cli.py" snapshot --issue <이슈 URL> --worktree <worktree> --slug <슬러그>
   # {"action": "commit", "task": "I-45", "path": ".ai/specs/I-45-ante.md", "updatedAt": "2026-11-04T01:02:03Z"}
   ```

   - `commit`이면 그 파일 하나를 `spec(I-<n>): 스냅숏 <updatedAt>`으로 커밋한다. **이 커밋 직후의 HEAD가 `<base>`다** — 구현 diff에 스냅숏이 섞이지 않는다.
   - `human / author_not_trusted`면 이슈 작성자가 쓰기 권한자(`OWNER`·`MEMBER`·`COLLABORATOR`)가 아니다. 진행하지 않고 사람이 필요한 것으로 `ask` 한다 — (h). 스냅숏은 이슈 본문만 담고 코멘트는 담지 않는다.
   - 진행자는 이후 이슈의 변화를 감시하지 않는다. 스냅숏을 읽는다 — 게이트 명령·변경 대상 파일·범위가 여기 있다.

그다음 태스크 하나를 끝까지 옮긴다:

4. 구현 워커 부트스트랩 — (d)
5. `worker-start` 후 대기 — (e)
6. 게이트 독립 재검증 — (f). **통과 즉시 구현 커밋한다. 리뷰 결과를 기다리지 않는다.**
7. 빈 diff 확인 후 리뷰 워커 기동(`<base>`를 spec에 넣는다) — (d), 리뷰 JSON 검증, 심각도 분기 — (g). 분기 결과와 무관하게 커밋은 이미 존재한다
8. PR 생성(경로 A) 또는 브랜치·커밋 목록 보고(경로 B) — (i)
9. **하위 워커 정리 → 보고 파일 → `worker_done`** — (i). 진행자 워커 자신의 해제는 설계 세션이 한다.
