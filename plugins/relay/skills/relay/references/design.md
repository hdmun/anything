# 설계 세션 절차 (b)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (설계 세션만 읽는다)

## (b) 설계 세션 절차

0. **Skill 도구로 Orca 스킬 `orchestration` 을 불러 Orca 가이드를 읽는다.** 설계 세션은 Run·Task·진행자 워커 감독만 다루므로 다른 Orca 스킬은 부르지 않는다(워크트리·터미널은 진행자 워커의 몫). 명령 문법은 가이드를 따른다.
   그리고 머신을 점검한다 — `python "$RELAY/scripts/relay_cli.py" doctor`. `FAIL`이면 진행자 워커를 띄우지 않고 출력의 `→` 줄을 사용자에게 전한다. 특히 `FAIL orca:nested-depth`면 진행자가 하위 워커를 띄울 수 없다(ADR 0004).
1. `grill-with-docs` 발동 기준: **새 개념/용어가 등장하거나, 되돌리기 어려운 결정이 포함되거나, spec을 쓰다 두 번 이상 막힐 때.** 그 외에는 바로 spec을 쓴다. 오탈자 수정 같은 것에까지 grilling을 걸지 않는다.
2. `.ai/specs/T-NNN-<슬러그>.md` 작성 — `references/spec-template.md`를 따른다.
   - **채번**: `NNN`은 `.ai/specs/` 안의 기존 파일 중 가장 큰 번호 + 1. 세 자리 0 패딩(`T-001`).
   - **위임 가치가 음수인 태스크를 구분할 것.** spec에 내용을 전부 적어야 하는 태스크(문서·규범·템플릿 authoring)는 위임하면 같은 내용을 두 번 쓰는 셈이고, 워커의 산출물은 spec의 전사에 그친다. 이런 태스크는 설계자가 직접 쓴다. 위임이 유효한 것은 **spec이 요구사항이고 산출물이 코드일 때**다.
   - **spec을 쓰기 전에 대상 코드를 직접 읽는다.** 구현을 읽어야 "이상해 보이지만 지금은 건드리면 안 되는 동작"을 미리 찾아낼 수 있고, 그걸 spec에 "이런 걸 만나면 고치지 말고 `ask`로 물어보라"로 적어둘 수 있다.
3. `run-create` 로 Run 을 만든다. objective 는 이번 목표 한 줄. 이미 있는 Run 을 이어 감독하는 세션이면 `run-use` 로 묶고 5로 간다.
4. `task-create` 로 태스크를 만든다. `--spec` 은 아래 한 줄, 의존이 있으면 `--deps <json_array>`.

   ```
   relay 진행자: Run <run_id> / T-NNN — <한 줄 요약>. spec: .ai/specs/T-NNN-<슬러그>.md
   ```

   - **첫머리 `relay 진행자: Run <run_id> / T-NNN`이 진행자 워커 안에서 relay 스킬을 부른다.** `worker-start --task`는 이 spec을 워커 프롬프트의 `=== TASK ===` 블록으로 넣는다.
   - **`--spec`에는 이 한 줄만 넣는다.** spec 전문의 정본은 git 파일이다.
   - 이유 세 가지: (1) 리뷰어가 SPEC_VIOLATION을 판정하려면 git에서 spec을 읽어야 한다 (2) spec 수정 이력이 diff로 남아야 한다 (3) Windows 명령행 길이 제한에 걸린다.
   - 의존 관계가 있으면 `--deps`로 DAG를 만든다. 실행은 순차지만 DAG는 처음부터 정의한다.
5. **감독 루프** — ready 태스크를 하나씩(순차) 진행자 워커에게 맡긴다. 루프의 순서와 끝은 Orca 가이드 「Canonical supervised loop」·「Completion accounting」을 따르고, relay가 정하는 것은 아래뿐이다.
   1) `task-list --ready` 로 다음 태스크를 꺼낸다. **spec이 `relay 진행자:`로 시작하는 태스크만 맡긴다** — 나머지는 진행자가 만든 하위 Task(구현·리뷰·수정 라운드)이고 그 진행자의 몫이다. 꺼낼 것이 없으면 6으로.
      - 방금 끝난 태스크에 의존하는 태스크면, 그 브랜치를 사람이 머지했는지 먼저 묻고 기다린다. 진행자는 `main`에서 워크트리를 만들기 때문이다(머지는 사람이 한다).
   2) 기동 인자를 결정기에 묻는다 — `python "$RELAY/scripts/relay_cli.py" model coordinator`. `launch`의 `model`·`effort`로 `worker-start --task <task_id> --worktree current --agent claude --model <model> --effort <effort>`. 영수증의 `launch.effective`를 사용자 보고용으로 적어 둔다.
      - `worker-start`가 실패하면 다시 띄우지 않고 Orca 가이드 `recovery-and-cleanup` reference를 따른다. 기동 실패는 (h) 「시도와 라운드」대로 센다.
   3) `check --wait` 로 기다린다(`--types worker_done,escalation,question`, timeout은 가이드 기본). 메시지마다:
      - `question` — 진행자의 `ask`다. (h) 「설계 세션이 답하는 법」대로 직접 답하거나 사람에게 넘긴 뒤 `reply`. 그다음 ack와 재대기.
      - `escalation` — 진행자는 `ask`로 묻게 되어 있으므로 예상 밖 신호다. 내용을 사람에게 그대로 전한다.
      - `worker_done` — 4)로.
      - 빈 대기·timeout은 체크포인트다. 가이드대로 3회 연속이면 `worker-list` projection을 본다.
   4) **`worker_done`을 확인한다 — 게이트는 다시 돌리지 않는다**(진행자의 몫, ADR 0004). 보고의 `--report-path`에서 워크트리·`<base>`·브랜치를 읽고 셋만 본다:
      - `python "$RELAY/scripts/relay_cli.py" commit-guard --worktree <worktree> --base <base>` 종료코드 0
      - `succeeded`면 리뷰 리포트 `.ai/reviews/T-NNN.r*.json`가 워크트리에 있다
      - `git -C <worktree> log --oneline <base>..HEAD`에 구현·리뷰 커밋이 있다

      셋 중 하나라도 어긋나거나 `--outcome failed`면 진행자 워커를 해제하지 않고 `worker-retain` 한 뒤 사람에게 보고한다(터미널이 증거다).
   5) 셋 다 맞으면 진행자의 `worker-release` → ack → 사용자에게 한 줄 보고(T-NNN, 결과, 브랜치 또는 PR URL, 커밋 수) → 1)로.
      - 설계 세션의 컨텍스트가 커졌으면 이 지점(진행자를 해제한 직후)에서 멈추고, 사용자에게 새 세션에서 "relay Run `<run_id>` 이어서 감독해줘"를 권한다. 새 세션은 3의 `run-use`로 이어 간다.
6. **끝** — 꺼낼 태스크가 없고 떠 있는 진행자 워커도 없으면 `worker-list --terminal-state reclaimable`이 비었는지 확인한 뒤, 사용자에게 Run 결과를 보고한다: 태스크마다 결과, 근거(브랜치·PR·리뷰 파일), 남은 블로커.
