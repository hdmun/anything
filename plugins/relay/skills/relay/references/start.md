# 진행자 세션 시작 (c)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (진행자 세션 시작)

## (c) 시작 — Run 하나에 한 번

0. **기동 줄을 읽는다.** `relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그>` 에서 구현 이슈와 슬러그를 읽는다. 기동 줄에 `/ 일괄 진행: …` 필드가 있으면 그 값을 적어 둔다. `finish.md`·`merge.md`·`stop.md` 가 쓴다. 없으면 일반 relay 다. T-NNN spec 경로나 `relay 진행자:` Task 면 SKILL.md 「진입」의 호환 한 줄대로 멈춘다.
   - 현재 디렉터리가 이슈 워크트리(`I-<n>-<슬러그>`)다. 이후 `<worktree>` 는 이 경로다.
1. **Skill 도구로 Orca 스킬 `orchestration` 과 `orca-cli` 를 불러 Orca 가이드를 먼저 읽는다.**
   진행자 세션은 Run 을 소유한 코디네이터다. 가이드의 감독 루프를 따른다. relay 문서는 orca 명령 문법을 적지 않는다 — 동사 이름과 relay가 정한 값만 적는다. **충돌하면 Orca 가이드가 옳고, 이 스킬을 고친다.**
   relay가 더하는 것은 명령 사용법이 아니라 그 위의 정책이다 — 역할 분리, 심각도 라우팅. **relay 정책은 `relay_cli.py`가 판정한다**(ADR 0001). 판정 규칙을 이 문서에서 다시 계산하지 않는다.
2. **머신을 점검한다** — `python "$RELAY/scripts/relay_cli.py" doctor`. handoff 가 이미 돌렸어도 다시 한다. 셸 명령이라 비용이 0이고, handoff 없이 띄우거나 재개할 때도 걸린다.
   - `FAIL`(종료코드 1)이면 시작하지 않는다. 출력의 `→` 줄(고치는 방법)을 담아 **멈춤 보고** 후 끝난다 — (h). 다시 돌리는 것은 사람이 같은 이슈로 handoff 할 때다.
   - 특히 `FAIL plugin`은 **이 세션이 읽은 SKILL.md가 설치본보다 낡았다**는 뜻이다. 낡은 절차로 진행하면 이미 고친 문제를 다시 밟는다.
   - `WARN`은 PR 본문 `warnings:` 에 적고 진행한다 — (i). 미검증 버전의 smoke 는 handoff 에서 사람이 정한다.
3. **태스크를 읽는다** — `python "$RELAY/scripts/relay_cli.py" handoff-check --issue <이슈 URL> --json`. `tasks` 가 태스크 목록이다(하위 이슈가 없으면 이슈 자체 하나). `FAIL` 이 있으면 멈춤 보고 — (h).
   - 태스크 의존은 트래커의 blocking 이다(하위 이슈마다 `blocked by`). 그것으로 DAG 순서를 정한다.
4. **기준선 게이트** — 워커를 띄우기 전에 태스크들의 게이트 명령을 한 번 돌려 기준선이 녹색인지 확인한다. 이것이 가장 자주 걸리는 함정이다.
   - **fresh worktree에는 의존성이 설치되어 있지 않다.** 저장소에 setup 훅이 없으면 직접 준비한다.
   - **기준선이 빨간 상태로 워커를 띄우면 안 된다.** 구현자가 자기 잘못과 환경 문제를 구분할 수 없고, 자체 게이트 루프를 환경 문제로 소진한다. 빨간 원인을 진행자가 풀 수 없으면 멈춤 보고 — (h).
   - 종료코드로 판정한다. 파이프로 넘기면 실패가 사라진다 — (f) 참조.
5. **Run 과 태스크 DAG** — `run-create` 로 Run 을 만든다(objective 는 부모 이슈 제목). 태스크마다 `task-create` 를 만들고 의존이 있으면 `--deps` 로 DAG 를 적는다. `--spec` 은 한 줄이다: `I-<n> <이슈 제목>. 이슈: <이슈 URL>`. spec 전문의 정본은 이슈다.
6. **어디서부터 할지 묻는다** — 재개든 처음이든 같다. 이슈 워크트리의 브랜치가 끝난 태스크를 안다.

   ```bash
   python "$RELAY/scripts/relay_cli.py" resume --worktree <worktree> --tasks <DAG 순서의 태스크 ID, 쉼표로>
   # {"action": "start", "task": "I-47", "done": ["I-46"]}
   ```

   - `start` 면 `done` 의 태스크는 Orca Task 를 완료로 정리하고 건너뛴다. `task` 부터 아래 「태스크마다」를 돈다.
   - `pr` 이면 모든 태스크가 끝났다 — (i).
   - 앞선 Run 에서 멈춘 태스크는 `done` 에 없으므로 처음부터 다시 돈다: **스냅숏을 다시 커밋하고**(사람이 고친 이슈를 읽는다), 그 커밋 직후가 새 `<base>` 이므로 라운드는 처음부터 센다. 리뷰 리포트 번호는 이어 간다(`rN` 을 덮어쓰지 않는다).

## 태스크마다 — `task-list --ready` 가 빌 때까지 차례로

1. **spec 스냅숏을 뜬다** — 워커를 띄우기 전에 한다. 정본은 구현 이슈이고, 스냅숏은 태스크 시작 시점의 고정 사본이다(ADR 0006). `<슬러그>` 는 그 하위 이슈 제목에서 짓는다(하위 이슈가 없으면 기동 줄의 슬러그).

   ```bash
   python "$RELAY/scripts/relay_cli.py" snapshot --issue <태스크 이슈 URL> --worktree <worktree> --slug <슬러그>
   # {"action": "commit", "task": "I-46", "path": ".ai/specs/I-46-ante.md", "updatedAt": "2026-11-04T01:02:03Z"}
   ```

   - `commit`이면 그 파일 하나를 `spec(I-<n>): 스냅숏 <updatedAt>`으로 커밋한다. **이 커밋 직후의 HEAD가 `<base>`다** — 구현 diff에 스냅숏이 섞이지 않는다. `updatedAt` 은 PR 본문을 쓸 때 다시 본다 — (i).
   - `human / author_not_trusted`면 이슈 작성자가 쓰기 권한자(`OWNER`·`MEMBER`·`COLLABORATOR`)가 아니다. 진행하지 않고 멈춤 보고 — (h). 스냅숏은 이슈 본문만 담고 코멘트는 담지 않는다.
   - 진행자는 이후 이슈의 변화를 감시하지 않는다. 스냅숏을 읽는다 — 게이트 명령·변경 대상 파일·범위가 여기 있다.
2. 구현 워커 기동 — (d) `implementer.md`
3. 대기 — (e)
4. 게이트 독립 재검증 — (f). **통과 즉시 구현 커밋한다. 리뷰 결과를 기다리지 않는다.**
5. 빈 diff 확인 후 리뷰 워커 기동(`<base>`를 spec에 넣는다) — (d) `reviewer.md`, 리뷰 JSON 검증, 심각도 분기 — (g). 분기 결과와 무관하게 커밋은 이미 존재한다.
6. 리뷰 `pass` 면 리포트 커밋에 `Relay-Done: I-<n>` 을 붙이고(`review.md`), 그 태스크를 Orca 가이드대로 완료로 정리한 뒤 다음 태스크로 간다.

모든 태스크가 끝나면 PR 하나 — (i).
