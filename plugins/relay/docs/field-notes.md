# relay 실측 사례 모음

스킬(`skills/relay/`)이 규칙 옆에 두던 실측 사례 서사를 옮겨 둔 사람용 기록이다. **스킬은 이 파일을 가리키지 않는다.** 규칙과 그 이유 한 줄은 스킬에 남아 있고, 날짜·태스크 번호·횟수가 든 서사만 여기 있다.

> **2.0.0 (2026-11-02) 에서 버린 우회.** relay 는 터미널 선기동(`terminal create` → `tui-idle` → `worker-start --terminal`), readiness 사다리, `$null=1; agy`·`codex --yolo` 명령줄, agy 로그의 `HandleUserInput` 전달 확인을 버리고 Orca 기본 경로 `worker-start --agent` 로 돌아갔다(ADR 0003, plan 트랙 0 실측: Orca 1.4.245 에서 agy 7/7·codex 4/4).
> **(역사)** 표시가 붙은 항목은 그 우회를 만든 사례다. 지금 절차의 근거가 아니라, 같은 증상이 다시 나타나면 무엇을 의심할지 알려 주는 기록이다.

## 설계

- **대상 코드를 먼저 읽은 효과.** 잘림 처리가 `maxLength`를 초과하는 문자열을 반환하는 것을 설계자가 미리 발견해 그 지침을 spec에 넣었고, 리뷰어가 정확히 그 지점에서 `ask`를 발동했다. 지침이 없었다면 리뷰어가 `BLOCKER`를 올리고 → 구현자가 구현을 고치고 → `SPEC_VIOLATION`으로 잡혀 라운드 2회가 낭비됐을 것이다.

## 시작

- **낡은 SKILL.md 실행 (T-007).** 1.2.3 설치 뒤에도 1.2.0 절차의 단독 `agy`로 띄워 9회 연속 timeout이 났다. `doctor` 의 `plugin` 검사가 이것을 잡는다(교훈은 지금도 유효하다).

## 구현 워커 기동

- **`--base-branch` 생략.** `defaultBaseRef: null`인 저장소에서 최신 `main`이 아니라 최초 커밋에서 분기되어, 워크트리에 소스가 거의 없는 상태로 만들어졌다.
- **fresh worktree에 의존성 없음.** 새로 만든 워크트리에서 `bun run test`가 `exit 1`이었고 원인은 `node_modules` 부재였다. `bun install`(약 34초) 후 `exit 0`이 되었다.
- **(역사) 단독 `agy` 기동 (2026-10-10, Orca 1.4.222).** 단독 `agy` — 1.3.3 11/11 실패, 1.2.17 간헐 실패. `'$null=1; agy'` — 1.2.17·1.3.3 7/7 통과(2~3초), `worker-start --terminal` 연결과 `worker_done`까지 정상.
- **(역사) 입력 유실 (poker-server T-004).** `worker-start --agent antigravity`가 `stage: input_accepted`를 돌려줬지만 agy 로그에 `HandleUserInput`이 0건이었고, 워커는 환영 화면에서 영원히 대기했다. 2회 연속.
- **(역사) 전달 확인이 없을 때의 비용 (T-004).** 지금은 Orca 의 `turnStart` 가 이 확인을 한다. 빈 대기 3회(30분)를 다 쓰고 나서야 유실을 알게 됐다.
- **`ok: true`인 준비 실패.** 준비 감지에 실패해도 `ok: true`가 왔다(`failedStage: agent_readiness`, `dispatch: null`).
- **`turn_start_unobserved`.** 입력창이 비어 있었다(전달 실패).

## 리뷰 워커 기동

- **codex 준비 감지 (T-004).** codex 0.159는 배너에서 라벨을 빼고 제목을 폴더 이름으로 바꿔 `agent_readiness timeout`이 났다. `terminal_title` 키를 넣으면 6초 안에 감지됐다.
- **`Hooks need review` (poker-server T-006).** ponytail 플러그인 갱신으로 hook 신뢰 해시가 어긋나 확인창이 떴고, 그 한 번으로 리뷰 Task가 `failed`가 됐다.
- **(역사) `--yolo` 누락.** 직접 띄우면 샌드박스 안에서 `worker_done` 전송이 응답 없이 멈췄다. 3분 뒤 codex가 스스로 끊고 "can't confirm delivery"를 냈고 Task는 `dispatched`에 남았다.
- **(역사) 샌드박스를 켠 경우 (2026-10-11).** `[windows] sandbox = "elevated"`는 첫 명령에서 UAC 설치 도우미를 띄우고 멈췄다(`.sandbox` 로그 `sandbox setup required`). `-a never -s workspace-write -c windows.sandbox=unelevated`는 읽기·쓰기는 확인창 없이 되지만 Orca 연결이 `EPERM`이었다(`network_access=true`로도 같음). `~/.codex/rules`로 `orca orchestration`만 허용하면 최소 권한이 가능하지만 codex 전역 설정이라 쓰지 않기로 했다(사용자 결정).
- **(역사) `--yolo` 기동 시험 (2026-10-11, codex 0.159.3·Orca 1.4.222, 버리는 Task).** 5회 — `tui-idle` 7~11초 통과, 4회는 `worker_done`까지 14초 안팎, 1회는 `turn_start_unobserved`로 입력이 유실됐다. 2026-10-06(Orca 1.4.200)에는 `Hooks need review` 화면에서 `tui-idle` timeout → `readiness --agent codex`가 `human / blocked_prompt`를 돌려줬다.
- **역할 파일 드리프트.** 커밋 정책을 바꿀 때 역할 파일을 함께 고치지 않아, 리뷰어가 `--uncommitted`로 빈 diff를 검증하게 된 적이 있다.

## 대기

- **승인창에서 멈춘 리뷰어 (T-007).** codex 리뷰어가 `git status --short`·`Get-Location` 승인창에서 멈췄는데 `agentWait`은 비어 있었다. 빈 대기 2회 뒤 화면을 읽고서야 알았다.
- **agy는 2층 신호가 없다 (T-004).** `liveness: unverifiable (missing_status)`, `nextAction: none`만 돌아왔다.
- **`agentWait: null`.** 워커가 트러스트 프롬프트에 멈춘 상태에서 `agentWait: null`이 반환된 적이 있다.

## 게이트

- **워커의 직접 커밋 (T-004 `dd95130`).** 트레일러 없는 커밋이 생겨 구현 라운드가 1 적게 세졌다.
- **파이프로 가려진 종료코드.** 이 함정에 걸려, 소스가 없어 컴파일이 불가능한 워크트리를 "게이트 통과"로 오판했다.
- **`tsc -b` 증분 빌드.** 머지 직후 `tsc -b`가 출력 없이 끝나 "오류 0건"으로 읽혔지만 재빌드를 건너뛴 것이었다.
- **접두사 grep.** `TS2688`만 남은 상태를 "오류 0건"으로 보고할 뻔했다. 더 나쁜 것은 이 grep을 spec의 인수 조건에 그대로 적어 구현자에게 넘겼다는 점이다. 설정을 건드리는 태스크였다면 구현자가 설정 오류를 만들어 놓고 "0건 달성"으로 보고했을 것이다.
- **의존성 미동기화.** 머지 후 main에서 `TS2688`이 되살아났고 원인은 `bun install` 미실행이었다.
- **변이 게이트 (poker-server T-007).** `tools/mutate/mutate.py`가 변이마다 `go test ./...` 전체를 돌려 25~40분 걸렸다. 변이 도중 다른 게이트를 돌리면 변이가 심어진 소스를 테스트해 거짓 FAIL이 났다(`internal/analysis`).

## 수정 라운드

- **`dispatch_inactive`.** `worker_done` 뒤 Dispatch는 `completed`가 되어 `send --to dispatch:<id>`는 항상 거부됐다.
- **(역사) 머리글 밀림 (T-007).** 3회 연속 timeout 뒤 새 터미널은 즉시 통과했다. 재생성 직후 첫 `worker-start`의 `agent_unconfigured`는 2회 관측됐고 `tui-idle` 재시도로 통과했다.
- **(역사) `/clear` (2026-10-11, agy 1.3.3).** `/clear` 뒤 머리글이 다시 찍혀 `tui-idle`은 통과했지만 대화 맥락도 지워졌다(기억시킨 단어를 `UNKNOWN`으로 답함).

## 에스컬레이션

- **기동 실패 예산 (T-004).** 구현·리뷰 Task 둘 다 3회 연속 실패(circuit-break) 직전까지 갔다.
- **(역사) `agent_readiness` 한 번으로 `failed`.** 새 Task + 같은 터미널로 기동에 성공했고 60초 안에 `HandleUserInput`을 확인했다. 지금은 같은 Task 에 `--retry-of` 로 재출발한다.

## 종료

- **`trustedWorkspaces` 누적.** 항목 16개 중 5개가 이미 삭제된 relay 워크트리였다.

## 2.0.0 전환 측정 (2026-11-02, Orca 1.4.245·agy 1.4.12·codex 0.159.3)

- **`worker-start --agent` 가 선기동 없이 통과.** agy 7/7(기동 6~7초, `turnStart: observed`), codex 4/4(기동 17초, Orca 가 붙인 인자로 `worker_done` 도착). release 는 매번 터미널을 닫았다(`closed_agent_terminal`).
- **trust·업데이트 프롬프트 재현 불가.** Orca 가 agy 를 띄우기 직전 워크트리를 `trustedWorkspaces` 에 넣는다. codex 는 `check_for_update_on_startup = true` 로 바꿔도 프롬프트 없이 떴다.
- **중첩 깊이 기본값 1.** 진행자 워커가 agy 하위 워커를 띄우자 `nested_worker_depth_exceeded`. 깊이 2 로 올린 뒤 하위 워커의 `worker_done` 은 설계 세션이 아니라 진행자 inbox 로 갔다.
- **`ask` 왕복.** 진행자의 질문이 기동 26초 뒤 설계 세션 `check --wait` 에 `question` 으로 왔고, `reply` → ack 뒤 진행자가 재개해 `worker_done` 까지 갔다.
