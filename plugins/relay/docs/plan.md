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
5. [x] 배포 — `.claude`·`.claude-max` 양쪽 `claude plugin update relay` → poker-server 세션 재시작 → T-004 재개 (기존 리뷰 Task 포기, 새 리뷰 Task)

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

- `--command agy` 로 모델 핀 가능 여부 — agy 에 `--model`·`--effort` 플래그가 있음(1.2.16 `--help`). 실측 전 / codex `--terminal` 경로
- ~~`worker-release` 가 수동 생성 터미널을 닫는가~~ → 닫지 않는다(`retained / external_terminal`, 2026-10-10). (i) 의 `terminal close` 가 필요하다
- 정착한 Task 에 decision gate 가 걸리는가
- ~~agy `auto_updater` 차단~~ → 예열로 대응(2026-10-02). 실행 중 교체는 확인됨: 기존 파일을 `agy.exe.<숫자>.old` 로 옮기고 새 파일을 놓는다(1.2.14 세션이 떠 있는 동안 1.2.16 설치). 예열은 `agy update`(동기) 사용
