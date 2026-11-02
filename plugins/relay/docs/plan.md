# relay 작업 계획 (2026-10-01 확정)

출처: 플러그인 검토 + poker-server T-004 장애 리포트 + grilling 세션(질문 1~19).
용어는 [CONTEXT.md](../CONTEXT.md), 구조 결정은 [ADR 0001](adr/0001-policy-in-code.md).

## 트랙 0 — 완료

- [x] codex 0.159.3 준비 감지 실패 원인 규명 및 해결 — `~/.codex/config.toml` 에
      `[tui] terminal_title = ["app-name","activity","project-name"]`, `check_for_update_on_startup = false`.
      원인: Orca 1.4.216 은 codex 배너의 `model:`/`directory:` 라벨 또는 제목 속 `codex` 로만 대기를 판정하는데 0.159 가 둘 다 없앴다.
- [x] CONTEXT.md, ADR 0001

## 트랙 1 — 핫픽스 v1.1.2 (`hdmun/relay-v1.1.2-hotfix`, 문서만)

1. [x] SKILL.md (d) 기동 절차
   - agy: `terminal create --command '$null=1; agy'` (v1.2.2) → `terminal wait --for tui-idle` → `worker-start --terminal`, 60초 내 전달 확인(`HandleUserInput`)
   - codex: 위 두 키를 사전 조건으로. `--model <config.toml 의 model> --effort high`
   - antigravity `--model` 서술 정정 (Orca 가 이제 지원)
2. [x] SKILL.md (e)(h)(i)
   - (e) agy 는 projection 이 `unverifiable`/`none` 만 준다 → 3층으로. `nextAction.argv` 에 `orca` 접두
   - (h) 라운드 용어 재정의. 기동 실패(전달 실패 포함) 2회 → 사람 호출, 자동 재시도 없음
   - (i) 수동 생성 터미널은 release 후 `terminal close`
3. [x] 빈 diff 차단 — SKILL.md (g) 리뷰 워커 기동 전 `git diff --stat <base>..HEAD` 가 비면 중단 / 템플릿: reviewer 빈 diff → `failed`, implementer gate.log 서브셸
4. [x] 모델 계열화 — SKILL.md 에서 버전 문자열 제거, `Reviewed-by:` 트레일러. spec-template ask 하드코딩 제거. `plugin.json` 1.1.2
5. [x] 배포 — `.claude`·`.claude-sub` 양쪽 `claude plugin update relay` → poker-server 세션 재시작 → T-004 재개 (기존 리뷰 Task 포기, 새 리뷰 Task)

## 트랙 2 — 구조 개편 v1.2.0 (`hdmun/relay-v1.2.0-testable`, 직접 구현)

1. [x] 골격 + roles (40분) — `tests/`(unittest), `scripts/relaylib/`, `scripts/relay_cli.py`, `.githooks/pre-commit`.
       TDD로: `.gitignore` 블록 없을 때 init 거부 버그, CRLF, 필수 키 검증, 미치환 자리표시자 정규식,
       Windows 파이프 출력 시 cp949 `UnicodeEncodeError` (stdout 을 UTF-8 로 재설정 — 지금은 `python -X utf8` 로 우회)
2. [x] trust + review (60분) — `trust add/remove/prune`, `validate-review`, `review-branch`, 라운드 수, `r(N-1)`/`rN` 반복 판정, `changes_requested` 정합 → SKILL.md 분기 표 대체
3. [x] orca + model (45분) — `startup`, `liveness`, `model reviewer` + T-004 픽스처 → SKILL.md (d)(e) 대체
   - `startup` 에 **준비 감지 오판 → 1회 재생성** 분기: `tui-idle` timeout 인데 화면(`terminal read --screen`)에 입력창(`>` 단독 줄)이
     보이고 차단 문구(trust/update/permission)가 없으면 `{"action":"recreate_terminal"}` — 터미널을 닫고 새로 만든다. Task 밖이라 예산 무관.
     재생성 후에도 timeout 이면 `{"action":"human"}`. 한 번만 허용한다(무한 재생성 방지).
   - 근거(poker-server T-004 수정 라운드, 2026-10-02): agy 1.2.14 가 로그아웃 상태로 떠 로그인하며 다시 그릴 때 상태줄이
     `Antigravity CLI` 머리글보다 **먼저** 스트림에 찍혔다. Orca 는 머리글 뒤의 `gemini…` 줄 + `>` 줄로 준비를 판정하므로
     화면은 정상인데 영원히 timeout. 새 터미널은 2초 만에 통과했다 — 그리기 순서 경합이다.
   - 픽스처: 위 스트림 순서(상태줄 → 머리글 → 로고 줄 → `>`)와 정상 순서 둘 다.
   - **재생성이 항상 듣지는 않는다**(poker-server T-005, 2026-10-03~04): 새 터미널 2개 모두 30초 timeout, `worker-start` 준비 대기도 실패 → Task `failed`.
     같은 터미널이 약 18시간 뒤 `tui-idle` 0.5초 통과(그 사이 확인용 입력 1회). 입력이 풀었는지 시간이 풀었는지 미확인 — `startup` 은 재생성 1회 전에
     `tui-idle` 재시도 3회(30초 간격)와 로그인 로그(`OAuth: authenticated successfully`) 확인을 먼저 한다. Orca 쪽 판정 함수는 마지막 `antigravity cli`
     머리글 뒤의 `>` 단독 줄과 `do you trust|sign in|…` 부재를 본다(app.asar 에서 확인) — 픽스처에 "머리글 뒤에 `>` 가 아직 없는 화면"을 추가한다.
   - `worker-start` 는 준비 감지에 실패해도 `ok: true` 를 돌려주고 Task 를 `failed` 로 만든다 → `startup` 이 `result.failedStage` 로 판정하게 한다.
4. [x] doctor + smoke + 예열 (75분) — codex 키 2개, 리뷰어 모델(models_cache 대조), 검증된 버전(`references/verified-cli.json`), 죽은 trust 정리(`--fix`) / smoke 는 `relay-smoke` 고정 워크트리
   - **agy 예열(`relay_cli.py warmup agy`)** — 자동 업데이트를 막지 않고, Task 밖에서 버전을 고정한 뒤 워커를 띄운다.
     워커 터미널을 만들기 전에(구현 기동, 수정 라운드 재기동 모두) 실행한다:
     1. agy 를 한 번 띄운다 → 최신 `cli-*.log` 에 `auto_updater` 줄을 기다린다
     2. `Spawned background update process with PID <n>` 이면 그 PID 가 끝날 때까지 대기(상한 5분, 넘으면 `human`)
        / `skipping update (fast path)` 이면 대기 없음
     3. 닫고 다시 띄워 `tui-idle` 통과와 `agy --version` 을 확인 → 결정 `{"action":"ready","version":...}`
        또는 `{"action":"human","reason":"readiness_after_update"}`
     4. 버전이 `verified-cli.json` 밖이면 결정에 `"unverified": true` — 진행은 하되 결과를 사용자에게 보고하고, Task 가 성공하면 사람이 목록에 추가한다
   - 근거: agy 업데이트는 백그라운드 프로세스로 돌고 실행 중인 세션을 막지 않으며 다음 실행부터 적용된다(로그 `auto_updater.go:334`, 15분 fast path).
     위험은 업데이트 자체가 아니라 **Task 도중 버전이 바뀌어** 새 TUI 가 Orca 준비 감지를 깨는 것이다. 예열은 그 실패를 Task 예산 밖으로 옮긴다.
   - SKILL.md (d) 3번 앞에 "예열" 단계를 넣는다.
5. [x] evals (45분) — 판단형 5케이스, `--model sonnet`, threshold 1.0, `--no-publish` → 통과 시 1.2.0

### 규약

- 결정기(`review-branch`, `liveness`, `startup`, `model`)는 stdout JSON 한 줄, 종료코드 0 (입력 오류 2).
- 검사기(`validate-review`, `diff-guard`, `doctor`)는 종료코드 0/1, 사유는 stderr 한 줄.
- 스크립트는 orca 명령을 조립하지 않는다 (ADR 0001).
- tests: pre-commit / evals: 버전 올리기 전 수동 / smoke: CLI 업데이트 후 수동.

## 전환 — Orca 스킬 위에서 동작하게 (2026-11-02 확정, v2.0.0, `hdmun/relay-orca-skills`)

출처: grilling 세션(Q1~Q15). 근거는 [ADR 0003](adr/0003-delegate-launch-to-orca.md)·[ADR 0004](adr/0004-design-session-supervises-coordinator.md),
용어는 CONTEXT.md 「Orca 가이드」「Orca 스킬」「설계 세션」「진행자 워커」. 측정 시점 버전: Orca 1.4.245, agy 1.4.12, codex 0.159.3.

### 목표 구조

```
[설계 세션 = relay 를 호출한 세션]   spec → run-create / task-create → ready 태스크마다 진행자 워커 기동·감독 (순차)
        │  worker-start --agent claude  (model coordinator 결정기가 --model·--effort 를 준다)
        ▼
[진행자 워커]   worktree create → 기준선 게이트 → trust → warmup → 하위 워커 기동 → 게이트 재검증 → 리뷰 분기 → PR → worker_done
        │  worker-start --agent antigravity / codex
        ▼
[구현자 agy]  [리뷰어 codex]

셋 다 ~/.agents/skills 의 Orca 스킬(orchestration·orca-cli)로 Orca 가이드를 읽는다.
진행자가 혼자 판단할 수 없는 것은 모두 ask → 설계 세션 → (직접 답 | 사람에게 넘긴 뒤 답).
```

### 확정된 결정

| 질문 | 결정 |
|---|---|
| Q1 | 명령 문법과 워커 기동 방식을 Orca 가이드에 맡긴다 (ADR 0003) |
| Q2 | 가이드는 Skill 도구로 Orca 스킬을 불러 읽는다. `doctor` 가 설치를 검사한다 |
| Q3 | 설계 세션은 `orchestration` 만, 진행자 워커는 시작할 때 `orchestration`·`orca-cli` 둘 다 |
| Q4·Q15 | 용어 「Orca 가이드」 확장, 「Orca 스킬」「설계 세션」「진행자 워커」 신설, "진행 세션"은 Avoid (CONTEXT.md 반영 완료) |
| Q5·Q9 | 워커도 범위에 넣는다. agy·codex 모두 `~/.agents/skills` 를 읽으므로 링크 작업은 없다. 역할 템플릿을 Orca 스킬 기준으로 고친다 |
| Q6·Q13 | 설계 세션 = relay 를 호출한 세션. Run 끝까지 순차 감독, 태스크마다 진행자 워커를 새로 띄우고 해제 (ADR 0004) |
| Q7 | 기동 전환 전에 smoke 측정. 에이전트별 3/3 통과해야 전환. 실패한 에이전트는 기존 선기동을 「Orca 기본과 다른 점」에 증거와 함께 남긴다 |
| Q8 | 워커 관찰은 orchestration 동사(`worker-list` projection, `worker-read`)만. 확인창 감지가 smoke 에서 실패하면 "새 에이전트 탭 = 터미널" 강제로 후퇴 |
| Q10 | ADR 0003·0004 작성 (반영 완료) |
| Q11 | 세션 판정: Orca preamble 이 있으면 진행자 워커, 없으면 설계 세션 |
| Q12 | 에스컬레이션은 진행자의 `ask` 로 설계 세션에. decision gate(`gate-create`·`gate-resolve`) 폐기 |
| Q14 | relay_cli 정리 목록 — 아래 트랙 3 |

### 실행 순서

```
트랙 0 측정 ──┬──> 트랙 1 세션 구조 ──> 트랙 3 기동 전환 ──> 트랙 5 마무리
트랙 2 스냅숏 제거 ┘                      트랙 4 워커 템플릿 ──┘
```

트랙 0 과 트랙 2 는 서로 기다리지 않는다. 트랙 1·3 의 범위는 트랙 0 결과가 정한다.

### 트랙 0 — 측정 (약 2시간, 버리는 Run 에서)

1. [ ] `smoke` 에 `worker-start` 경로 추가 (45분, TDD) — 지금 smoke 는 `terminal create` + 날 `terminal send` 라 Orca 기동 경로를 재지 않는다.
       `worker-start --spec <PING> --worktree <relay-smoke> --agent <a> [--model --effort]` → `startup` 해석 → `worker_done` 수신 또는 `worker-read` → `worker-release`.
2. [ ] agy 3회 (설정 모델 있음·없음 섞어서): 준비 대기 통과, 전달(`turn_started` 관측 여부 / 로그 `HandleUserInput`), `launch.effective.model`, `worker_done` 도착.
3. [ ] codex 3회 (`--model <reviewer model> --effort high`): Orca 가 `--yolo` 를 붙여 `worker_done` 이 막히지 않는가, `launch.effective`.
4. [ ] 확인창 감지: codex 업데이트 프롬프트(`check_for_update_on_startup = true` 임시)·agy trust 프롬프트(trust 미등록 워크트리)를 일부러 띄워 `worker-start` 영수증(`failedStage`)과 `worker-list` 의 `projection.attention` 에 무엇이 나오는가. **자동 응답하지 않는다.**
5. [ ] 진행자 워커 경로: `worker-start --agent claude --model sonnet --effort medium` 로 띄운 워커가
       (a) spec 첫 줄 `relay 진행자: …` 로 relay 스킬을 부르는가, (b) Skill 도구로 Orca 스킬을 부르는가,
       (c) 그 안에서 `worker-start --spec … --agent antigravity` 가 깊이 제한(`nested_worker_depth_exceeded`) 없이 되는가,
       (d) `ask` → 설계 세션 `check --wait` 수신 → `reply` → 진행자 재개가 되는가,
       (e) "새 에이전트 탭" 설정이 채팅일 때 `worker-read --source auto` 로 읽히는가.
6. [ ] 워커(agy·codex)가 `~/.agents/skills` 의 `orchestration` 스킬을 실제로 부르는가 (워커 transcript 로 확인).
7. [ ] 결과를 이 파일 「측정」 절과 `verified-cli.json` 에 기록.

판정:

| 결과 | 다음 |
|---|---|
| 2 또는 3 이 3/3 | 그 에이전트는 트랙 3 에서 `worker-start --agent` 로 전환 |
| 2 또는 3 이 3/3 미만 | 그 에이전트는 선기동 유지, SKILL.md 「Orca 기본과 다른 점」에 실패 증거 |
| 4 에서 projection 이 확인창을 못 잡음 | Q8 후퇴안: `doctor` 가 "새 에이전트 탭 = 터미널"을 검사, 화면 검사 유지 |
| 5(c) 또는 5(d) 실패 | **멈추고 사용자에게 묻는다** — ADR 0004 재검토 |

### 트랙 1 — 세션 구조 (ADR 0004, 약 3시간)

1. [ ] SKILL.md 「진입 약속과 세션 판정」: 판정을 Orca preamble 유무로 (Q11). 세션 표를 「설계 세션 / 진행자 워커」로. 「왜 세션을 둘로 나누는가」를 "진행자 워커를 태스크마다 새로" 근거로 고쳐 쓴다.
2. [ ] `references/design.md`: spec → run/task 생성 뒤 **감독 루프** 추가 — ready 태스크마다 진행자 워커 기동 → `check --wait` → `question` 에 답(직접 판단 또는 사람에게 넘김) → `worker_done` 확인(`commit-guard`·리뷰 리포트 존재·`git log <base>..HEAD`, 게이트 재실행 없음) → `worker-release` → 다음 태스크. 컨텍스트가 커지면 새 세션에서 `run-use`.
3. [ ] `references/escalation.md`: decision gate 절 삭제 → 진행자 `ask` 형식(질문 한 줄 + 리뷰 파일 경로 + 선택지)과 설계 세션의 답 규칙(근거까지 적는다). 사람 호출도 `ask` 로 올리고 설계 세션이 사람에게 전달. `ask` 30분 timeout 은 같은 메시지 ID 로 resume.
4. [ ] `references/start.md`: 진행자 워커 시작 절차로 — preamble 확인 → Orca 스킬 2개 → `doctor`(설계 세션이 이미 돌렸어도 다시 한다 — 비용 0) → `task-list` 대신 preamble 의 Task.
5. [ ] `references/finish.md`: 끝은 "세션 폐기"가 아니라 `worker_done --outcome succeeded|failed` + `--report-path`(브랜치·커밋 목록·PR URL). 하위 워커 정리 표는 유지.
6. [ ] `model coordinator` 결정기: 사용자에게 `claude --model …` 을 안내하던 `action: session` → `worker-start` 인자(`--model`·`--effort`)를 돌려준다. `model designer` 는 지금처럼 안내만 (TDD, `relaylib/orca.py session_model`).
7. [ ] evals: `spec-violation-escalate` 를 `ask`/`reply` 경로로 재작성, 새 eval `session-classify`(preamble 없으면 설계 세션으로 행동, 진행자 절차를 밟지 않음).

### 트랙 2 — Orca 스킬 진입과 스냅숏 제거 (ADR 0003 문서 부분, 약 2시간)

1. [ ] `references/start.md` (c)0: 셸 `orca skills get orchestration` → Skill 도구로 Orca 스킬 호출. 설계 세션은 `orchestration` 만 (Q3).
2. [ ] references 10개 파일에서 orca 명령 스냅숏(약 30개)을 걷어낸다. 남기는 것: 할 일, relay 정책과 그 이유, `relay_cli.py` 호출. 명령은 "Orca 가이드의 `<동사>`" 식으로 동사 이름만 가리킨다.
3. [ ] SKILL.md 에 「Orca 기본과 다른 점」 절 신설 (불변식 바로 아래 — 컴팩션 뒤에도 남게). 항목마다 무엇이 다른지·이유·근거 측정 날짜. 처음 채울 것: 워크트리를 `worker-start` 에 합치지 않음(기준선·trust), `check --wait` timeout, 트랙 0 에서 실패한 에이전트의 선기동.
4. [ ] `doctor`: `skill:orchestration`·`skill:orca-cli` 검사 (`~/.agents/skills/<이름>/SKILL.md` 존재, 없으면 `FAIL` + Orca 재설치 안내) (TDD, 20분).
5. [ ] `test_docs.py`: references 에 `orca <동사>` 스냅숏이 없음을 검사하는 테스트 추가(예외: 「Orca 기본과 다른 점」 절). 기존 `--command` 문자열 검사는 트랙 3 에서 정리.

### 트랙 3 — 기동 전환 (ADR 0003 코드 부분, 트랙 0 결과에 따라 에이전트별, 약 3시간)

| 구분 | 대상 |
|---|---|
| 삭제 | `readiness` 서브커맨드와 사다리(`TUI_IDLE_RETRIES`·`is_bare_agy`·`AGY_HEADER` 등), `AGY_LAUNCH_COMMAND`·`agy_launch_command`·`codex_launch_command`, `startup` 의 `wait_tui_idle` 분기, 재사용 터미널의 `header_scrolled_out` 처리, `references/readiness.md`, `test_orca.py` 의 readiness 테스트와 `tests/fixtures/orca/*-screen-*.txt` |
| 유지 | `trust`, `warmup`, `review-branch`·`diff-guard`·`commit-guard`·`validate-review` |
| 변경 | `model implementer`·`model reviewer`: 명령줄 대신 `worker-start` 인자 반환 / `liveness`: 입력을 `--screen`·`--terminal` 에서 `worker-list`·`worker-read` 로 / `Implemented-by:`·`Reviewed-by:` 트레일러: `launch.effective.model` 에서 / `smoke`: 트랙 0 의 `worker-start` 경로를 기본으로 |
| 트랙 0 결과에 따라 | agy 전달 확인(로그 `HandleUserInput`): Orca 가 antigravity `turn_started` 를 관측하면 삭제, 못 하면 유지 |

1. [ ] 위 표대로 `relaylib/orca.py`·`smoke.py`·`relay_cli.py` 수정 (TDD).
2. [ ] `references/implementer.md`·`reviewer.md`·`review.md`(수정 라운드 재사용)·`wait.md`: 기동은 `worker-start --agent`, 수정 라운드는 Orca 가이드의 「Reuse after settlement」를 따른다.
3. [ ] SKILL.md 불변식에서 `$null=1; agy`·`codex --yolo`·「터미널 → tui-idle → worker-start」 3줄 정리. `test_docs.py` 의 `test_agy_launch_command_matches_code`·`test_codex_terminal_launch_bypasses_sandbox`·`test_reused_terminal_is_checked_before_worker_start`·`test_invariants_live_in_skill_md_itself` 갱신.
4. [ ] evals: `startup-no-dispatch`·`update-prompt-blocked` 을 `--agent` 경로 영수증으로 재작성, `delivery-failed` 는 위 「트랙 0 결과에 따라」 행대로 재작성 또는 삭제.

### 트랙 4 — 워커 템플릿 (Q5·Q9, 약 40분)

1. [ ] `templates/implementer.md.tmpl`·`reviewer.md.tmpl`: "preamble 의 `orca orchestration ask` 를 그대로 쓴다" → "`orchestration` 스킬을 불러 워커 의무(heartbeat·ask·worker_done)를 따른다. preamble 이 정본이다".
2. [ ] `test_roles.py` 갱신, `/relay:init --check` 로 드리프트가 잡히는지 확인.

### 트랙 5 — 마무리와 배포 (약 1.5시간)

1. [ ] CONTEXT.md 「예열」 정의의 "워커 터미널을 만들기 전에" → "워커를 띄우기 전에" (트랙 3 이 선기동을 없앤 경우만).
2. [ ] README: 진입 약속(relay 를 호출한 세션이 설계 세션), 진행 세션 절 → 진행자 워커, 준비물에 Orca 스킬, 「알려진 한계」.
3. [ ] `docs/field-notes.md`: 버려진 우회(선기동·readiness 사다리)의 사례를 "역사" 로 표시.
4. [ ] `plugin.json` 2.0.0, evals 전체(`--model sonnet`, threshold 1.0) 통과 확인.
5. [ ] 배포: `claude plugin update relay` 를 설정 디렉터리마다 → 사용 중 저장소마다 `/relay:init` 로 역할 파일 갱신.

### 이번 범위가 아닌 것

- 병렬 실행 승격 (k) — 기준(연속 5개 무에스컬레이션)은 그대로.
- 정착한 Task 에 decision gate 가 걸리는지 확인 — gate 를 폐기하므로 「미검증」에서 지운다(트랙 1 에서).

## 후속 — T-007 진행 세션 보고 3건 (2026-10-11, v1.3.2)

T-007 은 v1.2.3 으로 성공 종료(구현 2·리뷰 2, r2 pass). 그 세션이 실측한 3건:

1. **codex 리뷰어가 읽기 명령마다 승인창에서 멈춤**(r1 `git status --short`, r2 `Get-Location`), `agentWait` 은 null 이라 liveness 가 못 잡음.
   - 원인: v1.2.3 의 `worker-start --agent codex` 는 샌드박스를 켠 채 띄운다. `[windows] sandbox = "elevated"` 는 샌드박스 사용자 재설치가 필요한 상태(`.sandbox` 로그 `sandbox setup required: sandbox users missing or incompatible with marker version`)라 명령마다 승인을 묻거나 UAC 도우미에서 멈춘다.
   - v1.2.5 부터 리뷰어는 `codex --yolo` 라 승인창이 뜨지 않는다. 최소 권한 대안을 실측: `-a never -s workspace-write -c windows.sandbox=unelevated` 는 읽기·쓰기 OK, Orca 연결 `EPERM`(network_access 로도 같음). `~/.codex/rules` 로 `orca orchestration` 만 허용하는 길은 사용자 결정으로 쓰지 않는다 → `--yolo` 유지.
   - 보강: `BLOCKED_RE` 에 codex 승인창 문구, `liveness --screen --empty-waits` — 빈 대기 1회째부터 화면의 확인창을 `human / blocked_prompt` 로.
2. **긴 세션 뒤 agy 터미널이 tui-idle 을 통과 못 함**(화면은 `>`·Idle 정상, 새 터미널은 즉시 통과).
   - 원인 확인(Orca 소스): 준비 판정은 PTY 꼬리(최대 2000줄·256 KiB)에서 `antigravity cli` 머리글 뒤의 `gemini…` 줄과 `>` 줄을 찾는다. 머리글이 밀려나면 영영 못 찾는다.
   - `readiness` 에 `header_scrolled_out`(재시도 없이 재생성), SKILL (g) 에 재사용 전 `tui-idle` 과 재생성 절차.
   - `/clear` 실측: 머리글은 다시 찍혀 통과하지만 대화 맥락도 사라짐(UNKNOWN) — 재사용의 의미가 없어 쓰지 않는다.
   - agy `--model claude-…` 로 띄워도 새 터미널은 2초에 통과(모델 줄이 `gemini` 가 아니어도 무관).
3. **변이 게이트 25~40분**(`tools/mutate/mutate.py` 가 변이마다 `go test ./...`) — 도구 개선은 poker-server 몫. SKILL (f) 에 백그라운드 실행·동시 테스트 금지·잔재 판별·커밋 시점 주의.

## 기능 — 역할별 model·effort 설정 파일 (2026-10-11, v1.3.0)

- `~/.relay/models.json`(사용자) + `.ai/relay-models.json`(저장소) 를 필드 단위로 겹친다. 정본은 `relaylib/models.py`, 근거는 `docs/adr/0002-model-settings-file.md`.
- 리뷰어 모델은 codex `config.toml` 의 `model` 과 분리 — 설정 파일에 없으면 `reviewer_model_unset`(폴백 없음). `config.toml` 은 사전 조건 키만 본다.
- 결정기: `model designer|coordinator|implementer|reviewer`, `models`. doctor 에 `models` 줄, smoke 가 설정의 agy 명령으로 리허설.
- 실측(agy 1.3.3, `-p` 모드): `--model gemini-3.8-flash --effort low` 통과 / `--model gemini-3.8-flash-low --effort high` → `conflicts with --effort` 로 즉시 거부 / `--model gemini-3.1-pro --effort xhigh` → `has no "xhigh" effort (available: low, high)` / 없는 모델은 목록과 함께 거부 / `--effort high` 단독은 기본 모델에 적용되어 통과.
- 실측(2026-10-11, agy 1.3.3·Orca 1.4.222): `$null=1; agy --model gemini-3.8-flash --effort low` 로 smoke 1/1 통과 — `tui-idle` 2.5초, 입력 전달(`HandleUserInput`) 확인. 같은 날 두 번째 실행은 `tui-idle` 14.5초로 통과(첫 회 2.5초와 편차 큼). 표본 2회라 실전 Task 에서 더 쌓는다. v1.3.1 코드(`models-init` 로 만든 파일을 smoke 가 읽음)로 agy 1/1(`tui-idle` 2.5초)·codex 1/1(`high`, 6.4초) 재통과 — 누적 agy 3/3, codex 2/2. 리뷰어도 같은 smoke 로 `codex --yolo -m gpt-6-luna -c model_reasoning_effort=medium` 1/1 통과(codex 0.159.3, `tui-idle` 6.6초, 전달 확인). (`--dir` 은 Orca 에 등록된 워크트리여야 한다: `plugins/relay` 는 `selector_not_found`, `C:/Users/hdmun/scripts` 는 통과)

## 측정 — 리뷰 워커도 터미널 선기동으로, codex 는 `--yolo` 필수 (2026-10-11, v1.2.5)

- 배경: `worker-start --agent codex` 는 시작 직후 확인창(`Hooks need review` 등)이 뜨면 timeout 한 번으로 리뷰 Task 가 `failed` 가 된다(T-006). 구현자처럼 Task 밖에서 `tui-idle` 을 통과시킨다.
- 버리는 Run(`run_d4c207f2b71c`)에서 codex 0.159.3·Orca 1.4.222 로 측정:

  | `--command` | 결과 |
  |---|---|
  | `codex -m … -c model_reasoning_effort=high` | `tui-idle` 7초, 전달 정상, 그런데 워커의 `orca orchestration send … worker_done` 이 3분간 응답 없음 → codex 가 끊음, Task `dispatched` 잔류 |
  | `codex --yolo -m … -c …` | 5회 중 4회 `worker_done` 14초 안팎. 1회는 `turn_start_unobserved`(입력창 비어 있음, Dispatch `pending`) |

- 원인: Orca 는 codex 를 직접 띄울 때 `--dangerously-bypass-approvals-and-sandbox` 를 기본으로 붙인다(`src/shared/tui-agent-permissions.ts`, 사용자 설정 덮어쓰기 없음). 우리가 띄우면 빠지고, `config.toml` 의 `sandbox = "elevated"` 안에서 `orca` CLI 가 Orca 와 통신하지 못하는 것으로 보인다. `--yolo` 는 같은 인자의 숨은 별칭이다(`--help` 엔 없음, 0.159.3 이 받음).
- `startup` 결정기: `state: outcome_unknown`/`turnStart: unobserved` → `confirm_delivery`(실패로 단정하지 않고 `dispatch-show` 의 `status` 로 확인, `pending` 이면 기동 실패). 1.4.222 의 최상위 `dispatchId` 도 읽는다.
- 이 경로는 `launch.effective` 가 비어 온다 — `Reviewed-by` 트레일러의 모델은 명령줄의 `-m` 값.

## 측정 — agy 준비 감지 실패의 원인은 단독 `agy` 실행 경로다 (2026-10-10, v1.2.2)

- agy 1.3.3 smoke 가 `tui-idle` 3/3 실패. Orca 스트림에 `Antigravity CLI 1.3.3` 머리글은 있는데 `>` 줄과 상태줄이 없었다. 화면에는 둘 다 있다.
- 같은 시각 비교(Orca 1.4.222, PowerShell 터미널):

  | `--command` | 1.2.17 | 1.3.3 |
  |---|---|---|
  | `agy` (단독) | 1/2 통과 | 0/11 통과 |
  | `$null=1; agy`, `$env:...; agy`, 제목 설정 후 `agy` | 2/2 통과 | 7/7 통과 (2~3초) |

- 맨 앞 토큰이 `agy` 면 Orca 가 시작 명령을 에이전트로 인식한다(`recognizeAgentProcessFromCommandLine`). 그 경로에서만 입력창이 스트림에 남지 않는다. 내부 경로는 읽지 않았다.
- 버리는 Run 으로 `worker-start --terminal` 확인: `failedStage` 없음 → `HandleUserInput` → `worker_done` 13초. 우리 터미널은 `worker-release` 가 닫지 않는다(`retained / external_terminal`).
- 조치: `AGY_LAUNCH_COMMAND = "$null=1; agy"`(orca.py) — smoke 와 SKILL (d)4 가 쓴다. 회귀 테스트 2개. smoke 3/3 통과 → 1.3.3 등록.
- 바로 아래 10-05 측정의 "시간대 경합" 결론은 이것으로 대체된다. 1.2.x 의 단독 실행은 간헐 실패라 그때의 '연속 실패 뒤 13회 중 12회 통과'와 모순되지 않는다. 1.3.3 에서 상시 실패로 바뀌어 드러났다.
- 버린 대안: 제목을 `agy` 로 설정 — 로그인 전에 통과할 수 있고, agy 하위 프로세스(MCP, 상태줄)가 제목을 덮어쓴다. `CLOUD_SHELL=true` — 통과하지만 agy 의 다른 동작(IDE 종류·인증)에 영향을 줄 수 있다.

## 사고 — T-007 이 1.2.3 설치 뒤에도 1.2.0 절차로 진행 (2026-10-10, v1.2.4)

- poker-server T-007 진행 세션이 `--command agy`(단독)로 띄워 tui-idle 9회 연속 timeout → 사다리 끝까지 가서 사람 호출.
  세션 transcript 의 스킬 경로가 `relay/1.2.0` — 설치본(1.2.3)이 아니라 세션 시작 때 읽은 낡은 SKILL.md 로 진행했다.
- 보고된 cp949 `UnicodeDecodeError` 는 세션이 즉석으로 쓴 `python -c "json.load(open(...))"` 에서 났다. `relay_cli readiness` 는 같은 파일을 utf-8 로 읽어 정상 판정했다.
- 조치: doctor `plugin` 검사(세션이 읽는 사본 < 설치본이면 FAIL), `readiness --command`(단독 agy 면 재시도 없이 `recreate_terminal / bare_launch_command`), 회귀 테스트 8개.
- tui-idle 을 건너뛰고 `worker-start --terminal` 을 거는 우회는 불가: `worker-start` 가 안에서 같은 준비 대기를 하고 실패하면 Task 가 `failed` 가 된다. `dispatch --inject` 는 감독(worker-list projection·worker-read·worker-release)을 잃는다 — SKILL (d) 서두에 이미 적혀 있다.

## 측정 — (대체됨) agy 준비 감지 실패는 버전이 아니라 시간대에 몰리는 경합이다 (2026-10-04~05)

- 처음엔 agy 1.2.16 smoke 가 `tui-idle` 3/3 실패해 버전 문제로 보였다. 이어서 **1.2.14(.old 실행 파일)도 3/3 실패**, 워크트리에서도 실패 — 연속 8회.
  그 뒤 같은 조건에서 **13회 중 12회 통과(약 2.3초)**, smoke 3/3 통과(전달 확인 포함). 실행 방식(PowerShell 직접 / smoke)과도 무관했다.
- 실패한 회차는 모두 Orca 가 판정에 쓰는 스트림(제어 문자를 지운 PTY 줄 목록)에 `>` 줄이 없었다. 화면에는 입력창이 있다 — 커서 이동으로 다시 그린 줄이 목록에 남지 않는다.
- agy `/config` 의 `Rendering Mode` 는 이미 `Native Terminal experience (inline)` 이었다 — 원인 아님.
- 결론: 되돌리기·업데이트 차단은 하지 않는다(효과 없음). smoke 는 재생성하며 최대 3회 시도하고 이력(`attempts`)을 남긴다.
  `readiness` 사다리(재시도 3 → 재생성 1)는 몰린 시간대엔 모자랄 수 있다 — 실전 데이터가 더 쌓이면 재생성 횟수를 조정한다.
- 확인한 부수 사실: 1.2.14 실행 파일이 `agy.exe.<숫자>.old` 로 남아 있다. 자동 업데이트를 끄는 환경 변수 `AGY_CLI_DISABLE_AUTO_UPDATE` 가 있다.

## 평가 결과 (2026-10-05, v1.2.0 릴리스 기준)

`claude plugin eval . --judge-model sonnet` — 5케이스 × 3회 × 2팔, $2.65, 10분 37초.

| 케이스 | 플러그인 있음 | 없음(기준선) |
|---|---|---|
| delivery-failed | 1.0 ×3 | 0 ×3 |
| spec-violation-escalate | 1.0 ×3 | 0 ×3 |
| startup-no-dispatch | 1.0 ×3 | 0.5 ×3 |
| update-prompt-blocked | 1.0 ×3 | 0.5 ×3 |
| handoff-not-relay | 1.0 ×3 | 1.0 ×3 (발동하지 않아야 하는 케이스) |

평균 Δ 0.6. dry-run 에서 relay 가 단순 위임에 발동하던 문제를 description 으로 고쳤다.

## 결정됨

- **구현자 자체 커밋** (2026-10-04, A안) — poker-server T-004 `dd95130` 은 agy 가 `git commit` 권한으로 직접 커밋한 것으로 보인다(트레일러 없음, 구현 라운드 1 적게 셈).
  (a) agy `permissions.allow` 에서 `command(git commit)` 제거 — 사용자가 직접. 단 `command(powershell)` 이 남아 있으면 우회 가능하므로 검사기가 실제 방어선이다.
  (b) `relay_cli.py commit-guard` — `worker_done` 뒤 `base..HEAD` 에 귀속 트레일러 없는 커밋이 있으면 사람 호출. 구현 템플릿에 "권한이 있어도 커밋하지 않는다" 추가.

## 별도 과제

- Orca 에 codex 0.159 배너 변경 버그 보고
- `~/.codex/hooks.json` 에서 Orca codex 상태 hook 이 빠진 원인
- codex 작업 중 터미널 제목이 working 으로 바뀌는지 (smoke 로 확인)

## 미검증 (smoke·실전에서 확인)

- `--command '$null=1; agy --model … --effort …'` 로 모델 핀 — 플래그는 `-p` 모드에서 실측(1.3.3), Orca `tui-idle` 통과는 smoke 1/1 (위 「기능」), 표본 추가 필요. codex `--terminal` 경로는 v1.2.5 에서 확인
- ~~`worker-release` 가 수동 생성 터미널을 닫는가~~ → 닫지 않는다(`retained / external_terminal`, 2026-10-10). (i) 의 `terminal close` 가 필요하다
- 정착한 Task 에 decision gate 가 걸리는가
- ~~agy `auto_updater` 차단~~ → 예열로 대응(2026-10-02). 실행 중 교체는 확인됨: 기존 파일을 `agy.exe.<숫자>.old` 로 옮기고 새 파일을 놓는다(1.2.14 세션이 떠 있는 동안 1.2.16 설치). 예열은 `agy update`(동기) 사용
