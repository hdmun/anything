# relay 작업 계획 (2026-10-01 확정)

출처: 플러그인 검토 + poker-server T-004 장애 리포트 + grilling 세션(질문 1~19).
용어는 [CONTEXT.md](../CONTEXT.md), 구조 결정은 [ADR 0001](adr/0001-policy-in-code.md).

## 트랙 0 — 완료

- [x] codex 0.159.3 준비 감지 실패 원인 규명 및 해결 — `~/.codex/config.toml` 에
      `[tui] terminal_title = ["app-name","activity","project-name"]`, `check_for_update_on_startup = false`.
      원인: Orca 1.4.216 은 codex 배너의 `model:`/`directory:` 라벨 또는 제목 속 `codex` 로만 대기를 판정하는데 0.159 가 둘 다 없앴다.
- [x] CONTEXT.md, ADR 0001

## 트랙 1 — 핫픽스 v1.1.2 (`hdmun/relay-v1.1.2-hotfix`, 문서만)

1. [ ] SKILL.md (d) 기동 절차
   - agy: `terminal create --command agy` → `terminal wait --for tui-idle` → `worker-start --terminal`, 60초 내 전달 확인(`HandleUserInput`)
   - codex: 위 두 키를 사전 조건으로. `--model <config.toml 의 model> --effort high`
   - antigravity `--model` 서술 정정 (Orca 가 이제 지원)
2. [ ] SKILL.md (e)(h)(i)
   - (e) agy 는 projection 이 `unverifiable`/`none` 만 준다 → 3층으로. `nextAction.argv` 에 `orca` 접두
   - (h) 라운드 용어 재정의. 기동 실패(전달 실패 포함) 2회 → 사람 호출, 자동 재시도 없음
   - (i) 수동 생성 터미널은 release 후 `terminal close`
3. [ ] 빈 diff 차단 — SKILL.md (g) 리뷰 워커 기동 전 `git diff --stat <base>..HEAD` 가 비면 중단 / 템플릿: reviewer 빈 diff → `failed`, implementer gate.log 서브셸
4. [ ] 모델 계열화 — SKILL.md 에서 버전 문자열 제거, `Reviewed-by:` 트레일러. spec-template ask 하드코딩 제거. `plugin.json` 1.1.2
5. [ ] 배포 — `.claude`·`.claude-max` 양쪽 `claude plugin update relay` → poker-server 세션 재시작 → T-004 재개 (기존 리뷰 Task 포기, 새 리뷰 Task)

## 트랙 2 — 구조 개편 v1.2.0 (`hdmun/relay-v1.2.0-testable`, 직접 구현)

1. [x] 골격 + roles (40분) — `tests/`(unittest), `scripts/relaylib/`, `scripts/relay_cli.py`, `.githooks/pre-commit`.
       TDD로: `.gitignore` 블록 없을 때 init 거부 버그, CRLF, 필수 키 검증, 미치환 자리표시자 정규식,
       Windows 파이프 출력 시 cp949 `UnicodeEncodeError` (stdout 을 UTF-8 로 재설정 — 지금은 `python -X utf8` 로 우회)
2. [ ] trust + review (60분) — `trust add/remove/prune`, `validate-review`, `review-branch`, 라운드 수, `r(N-1)`/`rN` 반복 판정, `changes_requested` 정합 → SKILL.md 분기 표 대체
3. [ ] orca + model (45분) — `startup`, `liveness`, `model reviewer` + T-004 픽스처 → SKILL.md (d)(e) 대체
   - `startup` 에 **준비 감지 오판 → 1회 재생성** 분기: `tui-idle` timeout 인데 화면(`terminal read --screen`)에 입력창(`>` 단독 줄)이
     보이고 차단 문구(trust/update/permission)가 없으면 `{"action":"recreate_terminal"}` — 터미널을 닫고 새로 만든다. Task 밖이라 예산 무관.
     재생성 후에도 timeout 이면 `{"action":"human"}`. 한 번만 허용한다(무한 재생성 방지).
   - 근거(poker-server T-004 수정 라운드, 2026-10-02): agy 1.2.14 가 로그아웃 상태로 떠 로그인하며 다시 그릴 때 상태줄이
     `Antigravity CLI` 머리글보다 **먼저** 스트림에 찍혔다. Orca 는 머리글 뒤의 `gemini…` 줄 + `>` 줄로 준비를 판정하므로
     화면은 정상인데 영원히 timeout. 새 터미널은 2초 만에 통과했다 — 그리기 순서 경합이다.
   - 픽스처: 위 스트림 순서(상태줄 → 머리글 → 로고 줄 → `>`)와 정상 순서 둘 다.
4. [ ] doctor + smoke + 예열 (75분) — codex 키 2개, 리뷰어 모델(models_cache 대조), 검증된 버전(`references/verified-cli.json`), 죽은 trust 정리(`--fix`) / smoke 는 `relay-smoke` 고정 워크트리
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
5. [ ] evals (45분) — 판단형 5케이스, `--model sonnet`, threshold 1.0, `--no-publish` → 통과 시 1.2.0

### 규약

- 결정기(`review-branch`, `liveness`, `startup`, `model`)는 stdout JSON 한 줄, 종료코드 0 (입력 오류 2).
- 검사기(`validate-review`, `diff-guard`, `doctor`)는 종료코드 0/1, 사유는 stderr 한 줄.
- 스크립트는 orca 명령을 조립하지 않는다 (ADR 0001).
- tests: pre-commit / evals: 버전 올리기 전 수동 / smoke: CLI 업데이트 후 수동.

## 별도 과제

- Orca 에 codex 0.159 배너 변경 버그 보고
- `~/.codex/hooks.json` 에서 Orca codex 상태 hook 이 빠진 원인
- codex 작업 중 터미널 제목이 working 으로 바뀌는지 (smoke 로 확인)

## 미검증 (smoke·실전에서 확인)

- `--command agy` 로 모델 핀 가능 여부 / codex `--terminal` 경로
- `worker-release` 가 수동 생성 터미널을 닫는가
- 정착한 Task 에 decision gate 가 걸리는가
- ~~agy `auto_updater` 차단~~ → 차단하지 않고 예열로 대응하기로 결정(2026-10-02, 트랙 2 4단계). 남은 미검증: Windows 에서 실행 중인 `agy.exe` 를 업데이트가 어떻게 교체하는지 — 예열 구현 중 확인
