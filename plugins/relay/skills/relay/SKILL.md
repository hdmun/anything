---
name: relay
description: Orca orchestration 위에서 설계자(Opus)·진행자(Sonnet)·구현자(agy)·리뷰어(codex) 4역할 파이프라인을 굴릴 때 사용한다. spec 작성부터 워커 dispatch, 게이트 재검증, 리뷰 심각도 분기, PR 생성까지를 다룬다.
---

# relay

`relay`는 3개 AI 코딩 에이전트를 Orca orchestration 위에서 연결하는 파이프라인의 코디네이터 스킬이다.

> **이 스킬 자체를 고칠 때**: 정본은 `scripts` 저장소의 `plugins/relay/` 이고, 설치본은 Claude Code가
> `plugins/cache/hdmun-scripts/relay/<version>/` 에 버전 경로로 두는 관리 복사본이다. 직접 고치지 않는다.
> 소스를 고친 뒤 `plugin.json` 의 `version` 을 올리고 `claude plugin update relay` 를 설정 디렉터리마다 실행한다.
>
> **저장소 쪽 역할 파일**(`.ai/roles/`)은 이 플러그인의 `templates/` 가 정본이다. 저장소에서 `/relay:init` 으로
> 생성하고, 플러그인을 업데이트한 뒤에는 `/relay:init --check` 로 드리프트를 확인한다(종료코드 1이면 드리프트).
> **역할 파일을 손으로 고치지 않는다** — 공유 규범은 `templates/` 를, 저장소 고유분은 `.ai/relay-roles.json` 을 고친다.

## 역할과 모델

| 역할 | 실행 주체 | 모델 / effort | Orca에서의 위치 |
|---|---|---|---|
| 설계자 | Claude Code | Opus / high | 코디네이터 자신 (워커 아님) |
| 진행자 | Claude Code | Sonnet 5 / medium | Run에 재바인딩, 태스크당 세션 폐기 |
| 구현자 | agy (Antigravity CLI) | 기본값(Flash Medium) — 핀 불가, (d) 참조 | supervised worker |
| 리뷰어 | codex | `gpt-5.6-luna` / high | supervised worker |

## 왜 세션을 둘로 나누는가

Claude Code는 매 턴 전체 컨텍스트를 재전송하므로 비용은 (컨텍스트 크기 × 턴 수)에 비례한다.
코디네이터 루프는 태스크당 10~20턴인데 판단 함량이 거의 없다(대부분 조건 분기).
반면 설계·명세·중재는 턴 수가 적고 판단 함량이 최대다.
따라서 잦고 긴 구간은 Sonnet에, 드물고 짧은 구간은 Opus에 배치한다.
Orca가 상태(Run/Task/Dispatch)를 소유하므로 세션을 버려도 잃는 것이 없다 — `run-use`로 재바인딩한다.

## 파이프라인 흐름

```
[설계 Opus·high]  /grill-with-docs  (발동 기준은 (b) 참고)
                    ├─ CONTEXT.md 갱신
                    └─ ADR 추가 (해당 시)
                  .ai/specs/T-NNN.md 작성
                  run-create / task-create --deps  → 세션 종료
                          ↓
[진행 Sonnet·med] run-use → 워커 부트스트랩 → worker-start
                          ↓
[구현 agy·medium] 구현 + 자체 게이트 루프
                          ↓
[진행]            게이트 독립 재검증
                          ↓
[리뷰 codex·high] .ai/reviews/T-NNN.rN.json 작성
                          ↓
[진행]            스키마 검증 → 심각도 분기 → PR 생성 → 워커 정리 → 세션 폐기
```

## (a) 두 세션의 구분

| 구분 | 설계 세션 | 진행 세션 |
|---|---|---|
| 실행 주체 | Claude Code Opus / high | Claude Code Sonnet 5 / medium |
| 하는 일 | spec 작성, run/task 생성, 심각도 판단(SPEC_VIOLATION 등) | 워커 부트스트랩, dispatch, 대기, 게이트 재검증, 리뷰 분기, PR 생성 |
| 끝나는 지점 | `task-create` 완료 후, Run ID를 사용자에게 알리고 세션 종료 | 태스크 하나가 성공 종료(i)되거나 사람 에스컬레이션이 발생한 직후 세션 폐기 |
| Orca에서의 위치 | 코디네이터 자신 (워커 아님) | Run에 재바인딩되는 코디네이터. 구현/리뷰는 워커로 dispatch |
| 판단 함량 | 최대 (새 개념, 되돌리기 어려운 결정) | 최소 (대부분 조건 분기) |

읽는 사람이 "지금 나는 어느 세션인가"를 판단하는 기준: **run-create/task-create를 아직 안 했으면 설계 세션, run-use로 기존 Run에 들어왔으면 진행 세션.**

## (b) 설계 세션 절차

1. `grill-with-docs` 발동 기준: **새 개념/용어가 등장하거나, 되돌리기 어려운 결정이 포함되거나, spec을 쓰다 두 번 이상 막힐 때.** 그 외에는 바로 spec을 쓴다. 오탈자 수정 같은 것에까지 grilling을 걸지 않는다.
2. `.ai/specs/T-NNN-<슬러그>.md` 작성 — `references/spec-template.md`를 따른다.
   - **채번**: `NNN`은 `.ai/specs/` 안의 기존 파일 중 가장 큰 번호 + 1. 세 자리 0 패딩(`T-001`).
   - **위임 가치가 음수인 태스크를 구분할 것.** spec에 내용을 전부 적어야 하는 태스크(문서·규범·템플릿 authoring)는 위임하면 같은 내용을 두 번 쓰는 셈이고, 워커의 산출물은 spec의 전사에 그친다. 이런 태스크는 설계자가 직접 쓴다. 위임이 유효한 것은 **spec이 요구사항이고 산출물이 코드일 때**다.
   - **spec을 쓰기 전에 대상 코드를 직접 읽는다.** 구현을 읽어야 "이상해 보이지만 지금은 건드리면 안 되는 동작"을 미리 찾아낼 수 있고, 그걸 spec에 "이런 걸 만나면 고치지 말고 `ask`로 물어보라"로 적어둘 수 있다.
     실측 사례: 잘림 처리가 `maxLength`를 초과하는 문자열을 반환하는 것을 설계자가 미리 발견해 그 지침을 spec에 넣었고, 리뷰어가 **정확히 그 지점에서 `ask`를 발동**했다. 그 지침이 없었다면 리뷰어가 `BLOCKER`를 올리고 → 구현자가 구현을 고치고 → `SPEC_VIOLATION`으로 잡혀 라운드 2회가 낭비됐을 것이다.
3. `orca orchestration run-create --objective "<목표>" --json`
4. `orca orchestration task-create --spec "<한 줄 요약 + spec 파일 경로>" [--deps <json_array>] --json`
   - **spec 전문을 `--spec`에 넣지 말 것.** 정본은 git 파일이고 `--spec`은 요약과 경로만 담는다.
   - 이유 세 가지: (1) 리뷰어가 SPEC_VIOLATION을 판정하려면 git에서 spec을 읽어야 한다 (2) spec 수정 이력이 diff로 남아야 한다 (3) Windows 명령행 길이 제한에 걸린다.
   - 의존 관계가 있으면 `--deps`로 DAG를 만든다. 실행은 순차지만 DAG는 처음부터 정의한다.
5. 세션 종료 — Run ID를 사용자에게 알려준다.

## (c) 진행 세션 절차

0. **`orca skills get orchestration`으로 정본 가이드를 먼저 읽는다.**
   이 스킬이 적는 orca 명령은 작성 시점의 스냅숏이다. 정본은 바이너리가 직접 서빙하고 릴리스마다 바뀐다 —
   Orca가 배포하는 `orchestration` 스텁이 *"캐시된 복사본에서 서브커맨드나 플래그를 추측하지 말라"* 고
   명시한 이유가 이것이다. **충돌하면 정본이 옳고, 이 스킬을 고친다.**
   relay가 더하는 것은 명령 사용법이 아니라 그 위의 정책이다 — 역할 분리, 심각도 라우팅, 세션 폐기 규범.
1. `orca orchestration run-use --id <run_id> --json`
2. `orca orchestration task-list --ready --json` 로 다음 태스크를 꺼낸다. **태스크 상태를 컨텍스트에 들고 있지 말고 매번 Orca에 물어본다** (외부 메모리로 사용).
3. 워커 부트스트랩 — (d)
4. `worker-start` 후 대기 — (e)
5. 게이트 독립 재검증 — (f). **통과 즉시 구현 커밋한다. 리뷰 결과를 기다리지 않는다.**
6. 빈 diff 확인 후 리뷰 워커 기동(`<base>`를 spec에 넣는다) — (d), 리뷰 JSON 검증, 심각도 분기 — (g). 분기 결과와 무관하게 커밋은 이미 존재한다
7. PR 생성(경로 A) 또는 브랜치·커밋 목록 보고(경로 B) — (i)
8. **워커 정리** — `worker-release` + `trustedWorkspaces` 해제. `reclaimable`이 0인지 확인한 뒤 세션 폐기 — (i), (j)

## (d) 워커 부트스트랩

**구현·리뷰 워커 모두 `worker-start`로 띄운다.** 정본은 이것을 정상 경로로 규정하고, `dispatch --inject`는
*"leaves an operator-created process unsupervised and is only for an expressiveness gap"* 라고 못박는다.
감독 워커라야 `worker-list`의 fleet projection, `worker-read`, `worker-release`가 열리며 — (e)와 (i)가 그것을 전제한다.
비감독 Dispatch는 Orca가 terminal state `retained`로 고정해 회수 대상에서 아예 빠진다.

**구현 워커(agy)**

1. `orca worktree create --repo <sel> --name T-NNN --base-branch main --setup run --json` 으로 worktree 경로를 확보한다.
   - **`--base-branch`를 반드시 명시한다.** 생략하면 repo의 `defaultBaseRef`를 쓰는데, 그 값이 `null`인 저장소에서는 엉뚱한 지점에서 분기된다. 실측 사례: `defaultBaseRef: null`인 저장소에서 최신 `main`이 아니라 **최초 커밋**에서 분기되어, 워크트리에 소스가 거의 없는 상태로 만들어졌다.
   - 만든 직후 `git -C <worktree> log --oneline -1`로 base가 의도한 커밋인지 확인한다. 어긋났으면 `git -C <worktree> reset --hard <base>`로 맞춘다(추적되지 않은 파일은 보존된다).
   - **이 커밋 SHA를 적어둔다.** 리뷰 워커의 Task spec에 `<base>`로 넣어야 한다.

   **그리고 worker-start 전에 게이트를 한 번 돌려 기준선이 녹색인지 확인한다.** 이것이 (d) 전체에서 가장 자주 걸리는 함정이다.

   - **fresh worktree에는 의존성이 설치되어 있지 않다.** 실측: 새로 만든 워크트리에서 `bun run test`가 `exit 1`이었고, 원인은 `node_modules` 부재였다. `bun install`(약 34초) 후 `exit 0`이 되었다.
   - `--setup run`은 저장소에 setup 훅이 있을 때만 이 일을 대신한다. 훅이 없거나 `--setup skip`을 썼다면 직접 준비한다.
   - **기준선이 빨간 상태로 워커를 띄우면 안 된다.** 구현자가 자기 잘못과 환경 문제를 구분할 수 없고, 게이트 자체 루프 3회를 환경 문제로 소진한 뒤 `escalation`을 올린다. 라운드 하나가 통째로 낭비된다.
   - 종료코드로 판정한다. 파이프로 넘기면 실패가 사라진다 — (f) 참조.

2. **`~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces` 배열에 그 worktree 경로를 추가한다.**
   - 등록하지 않으면 agy가 "Do you trust the contents of this project?" 프롬프트에서 멈춘다. **기동 방식과 무관하게 필수다.**
   - 더 나쁜 점: 사람이 프롬프트를 해소해도 **스크롤백에 남은 텍스트 때문에 감지가 풀리지 않는다.** 사전 등록이 유일하게 깨끗한 해법이다.
   - `worktree create`는 경로를 슬래시(`C:/Users/...`)로 반환하지만 기존 항목은 백슬래시다. **반드시 백슬래시로 정규화해서 넣는다.**
   - 성공 종료 때 이 항목을 지운다 — (i)의 「워커 정리」. 지우는 단계가 없으면 단조 증가한다.

   ```bash
   python - "<worktree path>" <<'PY'
   import json, sys, pathlib
   p = pathlib.Path.home() / ".gemini/antigravity-cli/settings.json"
   s = json.loads(p.read_text(encoding="utf-8"))
   ws = s.setdefault("trustedWorkspaces", [])
   new = sys.argv[1].replace("/", "\\")
   if new in ws:
       print("already trusted:", new)
   else:
       ws.append(new)
       p.write_text(json.dumps(s, ensure_ascii=False, indent=2), encoding="utf-8")
       print("added:", new)
   PY
   ```

3. **터미널을 먼저 띄우고, 준비된 뒤에 감독을 건다.** `worker-start --agent antigravity`로 한 번에 띄우지 않는다.

   ```bash
   orca terminal create --worktree id:<wt> --title "T-NNN agy" --command agy --json
   orca terminal wait --terminal <h> --for tui-idle --timeout-ms 30000 --json
   orca orchestration worker-start --task <id> [--retry-of <dispatch_id>] --worktree id:<wt> --terminal <h> --json
   ```

   - **이유**: agy는 입력창이 준비되기 전에 들어온 입력을 **조용히 버린다.** Orca는 antigravity의 전달 여부를 관측하지 못해(`provider: unsupported`) 경고도 없다.
     실측(poker-server T-004): `worker-start --agent antigravity`가 `stage: input_accepted`를 돌려줬지만 agy 로그에 `HandleUserInput`이 0건이었고, 워커는 환영 화면에서 영원히 대기했다 — 2회 연속.
   - `tui-idle`을 건너뛰고 바로 `worker-start --terminal`을 걸면 `agent_unconfigured`로 거부된다. Orca가 터미널에 `agentIdentity: antigravity`를 태깅하기 전이기 때문이다.
   - `tui-idle`이 timeout이면 `worker-start`를 걸지 않는다 — Task 밖에서 실패한 것이라 기동 실패 예산을 쓰지 않는다. 터미널 화면을 확인하고 사람을 부른다.
   - `--terminal`은 `--model`/`--effort`와 함께 쓸 수 없으므로 구현자는 **agy 기본 모델**로 뜬다.
     (`worker-start --agent antigravity --model`은 이제 Orca가 지원하지만, 위의 유실 문제 때문에 그 경로를 쓰지 않는다.)
   - **응답에 dispatch가 비어 있으면**(이 경로에서는 보통 그렇다) `orca orchestration dispatch-show --task <task_id> --json`으로 조회한다. 추측하지 말 것.

4. **60초 안에 전달을 확인한다.** Orca의 "입력 수락"은 전달의 증거가 아니다.

   ```bash
   # 가장 최근 agy 로그에 HandleUserInput 줄이 생겼는지 본다
   ls -t ~/.gemini/antigravity-cli/log/cli-*.log | head -1 | xargs grep -c "HandleUserInput called with text:"
   ```

   - 1 이상이면 전달됨 — (e)의 대기로 넘어간다.
   - 0이면 **전달 실패 = 기동 실패**다. 재시도하지 않고 `worker-retain` 후 사람을 부른다 — (h).
     이 단계가 없으면 빈 대기 3회(30분)를 다 쓰고 나서야 유실을 알게 된다(T-004 실측).

**리뷰 워커(codex)**

사전 조건 — `~/.codex/config.toml`에 다음 두 키가 있어야 한다. 없으면 기동하지 말고 사용자에게 추가를 요청한다.

```toml
check_for_update_on_startup = false          # 최상위. 업데이트 프롬프트가 기동을 막는다 (agent_prompt_blocked)

[tui]
terminal_title = ["app-name", "activity", "project-name"]   # 제목에 "codex"가 있어야 Orca가 준비를 감지한다
```

- 두 번째 키가 필요한 이유: Orca(1.4.216)는 codex가 준비됐는지를 **배너의 `model:`/`directory:` 라벨**이나 **터미널 제목 속 `codex`** 로만 판정한다.
  codex 0.159는 배너에서 라벨을 빼고 제목을 폴더 이름으로 바꿔 둘 다 사라졌고, 그 결과 `agent_readiness timeout`이 난다(T-004 실측). 이 키를 넣으면 6초 안에 준비가 감지된다.
- 모델은 **codex 기본 모델을 따른다.** `config.toml`의 최상위 `model` 값을 읽어 넘긴다. `--effort`는 `--model` 없이 쓸 수 없으므로 둘을 함께 준다.

**기동 전에 리뷰할 diff가 실제로 있는지 확인한다.** 빈 범위를 넘기면 리뷰어는 아무것도 검증하지 않고 `pass`를 낸다 — 정상 통과와 구분되지 않는 가장 비싼 실패다.

```bash
git -C <worktree> diff --stat <base>..HEAD | tail -1
```

- 출력이 비어 있으면 **리뷰 워커를 띄우지 않는다.** `<base>`가 틀렸거나 (f)의 구현 커밋이 빠진 것이다. 둘 중 무엇인지 확인하고 고친 뒤 다시 본다.
  알아낼 수 없으면 사람을 부른다. 이 확인은 셸 명령이라 비용이 0이다.
- 리뷰어 역할 파일에도 같은 확인이 있다(빈 diff면 `--outcome failed`). 진행자 쪽 확인이 1차, 역할 파일 쪽은 템플릿이 갱신된 저장소에서만 동작하는 2차 방어다.

- `orca orchestration worker-start --task <id> --worktree id:<구현과 같은 worktree> --agent codex --model <config.toml의 model> --effort high --json`
- **구현 워커와 같은 worktree를 쓴다.** 파이프라인이 순차라 충돌이 없다. (f)에서 게이트 통과 즉시 구현 커밋을 만들어두므로, 리뷰어는 `codex review <base>..HEAD`처럼 커밋된 범위를 본다 — `--uncommitted`를 전제하지 않는다.
- **그 `<base>`를 Task spec에 반드시 적는다.** 리뷰어는 base를 추측할 수 없고, 범위를 잘못 잡으면 **조용히 빈 diff를 보고 `pass`를 낸다.** 정상 통과와 구분되지 않으므로 이 파이프라인에서 가장 비싼 실패다. 1번에서 적어둔 커밋 SHA를 그대로 넣는다.
- 저장소의 역할 파일(`.ai/roles/reviewer.md`)도 같은 전제로 맞춰져 있어야 한다. **커밋 정책을 바꿀 때 역할 파일을 함께 고치지 않으면 리뷰어가 `--uncommitted`로 빈 diff를 검증하게 된다** — 실측으로 드리프트가 발생했던 지점이다. `/relay:init --check`로 확인한다.
- **codex는 `--model`/`--effort`가 정상 전달된다.** 응답의 `launch.effective`(예: `{"agent":"codex","model":"<model>","effort":"high"}`)로 확인하고 `model`을 기록한다 — 리뷰 리포트 커밋의 트레일러에 쓴다.

**Git Bash 주의** — `terminal send --text "/clear"` 처럼 `/`로 시작하는 인자는 Git Bash가 `C:/Program Files/Git/clear`로 경로 변환한다. `MSYS_NO_PATHCONV=1`을 앞에 붙인다.

## (e) 대기와 무응답 판정

- `orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 600000 --json`
- **stdout만 파이프할 것.** `--wait` 중 stderr로 keepalive(`{"_keepalive":true}`)가 나오므로 `2>&1`로 합치면 파서가 깨진다.
- `question`이 오면 답하고 다시 대기한다. 순서는 다음과 같다:

```bash
# 1) question 수신 — 응답에서 msg_id 와 deliveryId 를 모두 뽑아둔다
orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 600000 --json

# 2) 답변
orca orchestration reply --id <msg_id> --body "<답>" --json

# 3) ack 와 재대기를 한 번에 — 이 delivery 를 ack 하지 않으면 같은 배치가 재전달된다
orca orchestration check --ack <delivery_id> --wait --types worker_done,escalation,question --timeout-ms 900000 --json
```

  워커의 질문에 답할 때는 **판단의 근거까지 적는다.** 워커는 spec과 역할 파일만 알고 이 대화를 모르므로, "승인"만 보내면 다음 유사 상황에서 또 물어본다. 어느 spec 항목에 근거했는지, 그 발견을 finding으로 올릴지 말지까지 함께 지시한다.

### 빈손으로 돌아왔을 때

**빈 대기와 타임아웃은 실패가 아니라 체크포인트다.** 순서대로 내려간다.

**1층 — 3회까지는 그냥 기다린다.** `check --wait`를 다시 건다. heartbeat나 화면 활동은 *살아 있다*는 뜻이지 *끝났다*는 뜻이 아니다.

**2층 — 3회 연속 빈 대기면 fleet projection을 본다.** 감독 워커에만 존재하는 신호이고, 추측 없이 다음 행동을 문자열로 준다.

```bash
orca orchestration worker-list --run <run_id> --include-remote --json
```

- `projection.attention.requiresAction`이 `true`이고 `projection.nextAction.kind`가 `none`이 아니면 **`nextAction.argv`를 실행한다.** 실측으로 `{"kind":"release","argv":[...]}`가 돌아온 사례가 있다.
  `argv`에는 실행 파일명이 빠져 있다(`["orchestration","worker-release",...]`) — **앞에 `orca`를 붙여** 실행한다.
- `projection.liveness.verdict`가 `exited`면 양성 증거다. `unverifiable`은 **부재이지 증거가 아니다.**
- **agy 워커는 2층이 답을 주지 않는다.** 실측(T-004): `liveness: unverifiable (missing_status)`, `nextAction: none`만 돌아왔다. agy는 2층을 건너뛰고 바로 3층으로 간다.

**3층 — `nextAction.kind`가 `none`이면 벽시계로 판정한다.** 정본은 여기서 *"`liveness.reason`을 읽고 계속 기다려라"* 라고만 하는데, 그건 종료 조건이 없다. relay는 여기에 임계값을 둔다.

| 관측 | 해석 | 행동 |
|---|---|---|
| `agentWait` ≠ null | 프롬프트에 멈춤 | **사람 호출** (자동 응답 금지) |
| `lastOutputAt`이 기준시간 이내 | 작업 중 | 1층으로 돌아가 계속 대기 |
| `lastOutputAt`이 기준시간 이상 정지 | 조용히 멈춤 | **사람 호출** |

기준시간은 구현 워커 **5분**, 리뷰 워커 **10분**이다.
**사람 호출은 상태를 바꾸지 않으므로 안전한 종료 조건이다.** 정본이 금지하는 것은 부재를 근거로 `stop`·`abandon`·`retry`·`release`하는 것이지, 사람을 부르는 것이 아니다.

**`agentWait`는 양성 신호로만 믿는다.** 값이 있으면 실제로 멈춘 것이지만, `null`은 안 멈췄다는 증거가 아니다.
정본도 같은 말을 한다 — *"`unverifiable` is absence, including when `worker-show` reports `agentWait` null."*
실측으로도 워커가 트러스트 프롬프트에 멈춘 상태에서 `agentWait: null`을 반환한 적이 있다.
그래서 `agentWait`·`tui-idle`·heartbeat 중 **어느 것도 1차 신호가 아니다.** 2층의 projection이 1차이고, 그것이 답을 못 줄 때만 3층의 `lastOutputAt`을 본다.

**프롬프트 자동 응답은 금지한다.** `trustedWorkspaces` 사전 등록으로 알려진 프롬프트는 이미 제거했으므로, 남은 프롬프트는 예상 밖의 것이고 사람이 봐야 한다.

## (f) 게이트 독립 재검증

워커가 자체 루프로 게이트를 돌리지만, `worker_done` 수신 후 **진행자가 같은 게이트를 직접 다시 실행한다.**

- 이유 1: 워커의 자체 보고를 신뢰하되 검증한다.
- 이유 2: 셸 명령이라 LLM 토큰을 쓰지 않는다 — 사실상 공짜다.
- 이유 3: **게이트를 통과하지 못한 코드를 리뷰 워커에게 넘기면 codex 토큰이 낭비된다.**

**워커가 정직하다는 관측이 쌓여도 이 단계를 빼지 않는다.** 셸 명령이라 LLM 비용이 0이므로, 신뢰가 쌓였다는 것은 이 단계를 뺄 근거가 되지 못한다. 비용이 0인 검증을 없애서 얻는 것은 없고, 한 번의 거짓 완료를 놓치면 그 뒤 모든 라운드가 오염된다.

게이트 명령은 repo마다 다르며 spec의 인수 조건에 명시된다.
예를 들어 Go repo라면 `go build ./... && go vet ./... && go test ./...` 이다.

**게이트는 반드시 종료코드로 판정한다.** 출력을 파이프로 넘기면 파이프라인의 마지막 명령이 종료코드를 결정하므로 앞 명령의 실패가 사라진다.

```bash
# 잘못됨 — head의 종료코드를 보게 되어 실패해도 통과로 읽힌다
go build ./... 2>&1 | head -3 && echo "OK"

# 올바름
go build ./... ; echo "build exit=$?"
go test  ./... > gate.log 2>&1 ; echo "test exit=$?"
```

실제로 이 함정에 걸려, 소스가 없어 컴파일이 불가능한 워크트리를 "게이트 통과"로 오판한 사례가 있다. **워커의 보고를 검증하려고 만든 단계가 스스로 거짓 양성을 내면 그 단계는 없느니만 못하다.**

### 측정 명령이 거짓 양성을 내지 않게 하는 세 가지

종료코드 함정 외에 실측으로 걸린 것이 셋 더 있다. 모두 "검증했다고 믿었는데 사실은 아무것도 검증하지 않은" 경우다.

**1. 증분 빌드 도구는 캐시를 무효화하고 돌린다.**
`tsc -b`는 `.tsbuildinfo`를 보고 최신이라고 판단하면 아무 일도 하지 않고 조용히 끝난다. 실측: 머지 직후 `tsc -b`가 출력 없이 끝나 "오류 0건"으로 읽혔지만, 실제로는 재빌드를 건너뛴 것이었다.

```bash
# 검증 목적이면 항상 강제 재빌드
./node_modules/.bin/tsc -b --force > tsc.log 2>&1 ; echo "exit=$?"
```

**2. 오류를 셀 때 파일 접두사 없는 줄을 놓치지 않는다.**
컴파일러는 파일에 귀속되지 않는 **설정 수준 오류**를 파일 경로 없이 출력한다(예: `error TS2688: Cannot find type definition file for 'node'.`). `grep -E "^packages/.*error TS"` 같은 패턴은 이런 줄을 통째로 건너뛴다.

```bash
# 위험 — 설정 오류가 안 잡힌다
grep -E "^packages/.*error TS" tsc.log | sort -u | wc -l

# 안전 — 파일 유무와 무관하게 센다
grep -cE "error TS[0-9]+" tsc.log
```

실측: 이 패턴 때문에 `TS2688`만 남은 상태를 "오류 0건"으로 보고할 뻔했다. **더 나쁜 것은 이 grep을 spec의 인수 조건에 그대로 적어 구현자에게 넘겼다는 점이다.** 설정을 건드리는 태스크였다면 구현자가 설정 오류를 만들어놓고 "0건 달성"으로 보고했을 것이다. 수치 인수 조건을 쓸 때는 **측정 명령이 무엇을 놓치는지** 먼저 확인한다.

**3. 매니페스트가 바뀌었으면 의존성을 다시 설치하고 잰다.**
머지로 `package.json`/lockfile이 갱신되어도 체크아웃의 `node_modules`는 그대로다. 실측: 머지 후 main에서 `TS2688`이 되살아났고 원인은 `bun install` 미실행이었다.

- 머지 후 검증 전에 의존성을 동기화한다.
- 새 워크트리에서는 (d)의 기준선 확인이 같은 일을 한다.

### 게이트 통과 즉시 커밋한다

리뷰 결과를 기다리지 않고, 게이트가 초록이면 그 자리에서 구현자 커밋을 만든다.

- **이유**: 리뷰가 `SPEC_VIOLATION`이나 `BLOCKER`를 올려도 이미 코드는 게이트를 통과한 유효한 산출물이다. 커밋을 리뷰 결과 뒤로 미루면 에스컬레이션이 걸릴 때마다 워크트리에 커밋 안 된 변경만 남고, 사람이 diff로 확인할 수 있는 이력이 없다.
- 커밋 이후 리뷰나 사람이 수정을 요구하면 그 수정은 **새 커밋**으로 쌓는다. 기존 커밋을 amend하지 않는다 — 라운드마다 커밋이 남아야 몇 번째 라운드에서 무엇이 고쳐졌는지 `git log`로 보인다.
- 커밋 메시지에 태스크 ID와 구현자 모델을 적는다. 제목은 `feat(T-NNN): ...`, 본문 끝에 **트레일러 형식으로** `Implemented-by: agy/<launch.effective.model>` (예: `agy/gemini-3.8-flash-medium`).
  모델명은 추측하지 말고 `worker-start` 응답의 `launch.effective`에서 읽는다.
  **산문(`구현: agy / ...`)이 아니라 트레일러여야 한다.** 포맷이 갈리면 `git log --format='%(trailers:key=Implemented-by)'` 같은 기계 판독이 깨지고, "`git log`만 보고 어느 단계가 무엇을 만들었는지 가린다"는 목적 자체가 무너진다.
- 이 커밋 하나로 (g)의 심각도 분기 전체가 "커밋할지 말지"가 아니라 "다음 라운드를 여는지"만 정하면 되게 바뀐다.

## (g) 리뷰 결과 처리

리뷰어는 `.ai/reviews/T-NNN.rN.json`(`N`은 리뷰 라운드 번호, 1부터)을 쓰고 `worker_done`의 `--report-path`로 경로를 넘긴다.

**라운드마다 파일을 따로 남기는 이유는 (h)의 카운터 때문이다.** 진행 세션은 태스크마다 폐기되므로 라운드 수를 컨텍스트에 들고 있을 수 없다. 파일 개수가 곧 라운드 수이고, git에 남아 세션과 무관하게 유지된다.

진행자는 `references/review-schema.json`에 맞는지 검증한다.
형식 위반이면 재작성을 요구한다 — 비용은 리뷰 1회 재실행뿐이다.

### 수정 라운드는 새 Task + 새 Dispatch로 만든다

**워커가 `worker_done`을 보내는 순간 그 Dispatch는 `completed`가 되고, `send --to dispatch:<id>`는 `dispatch_inactive`로 거부된다.** Orca가 *"its worker will never read that mailbox"* 라며 명시적으로 막는다. 실측으로 확인된 동작이다. 따라서 수정 지시를 기존 dispatch에 보내려는 시도는 반드시 실패한다.

```bash
orca orchestration task-create \
  --task-title "T-NNN 수정 라운드 N" \
  --parent <원래 task_id> \
  --spec "T-NNN 리뷰 지적 수정. 리뷰: .ai/reviews/T-NNN.rN.json / 원본 명세: .ai/specs/T-NNN-<슬러그>.md" --json

orca orchestration worker-show --dispatch <이전 dispatch_id> --json
orca orchestration worker-start --task <새 task_id> --terminal <agent_terminal_handle> --json
```

- **워커 터미널은 살아 있으므로 같은 handle을 재사용한다.** 세션 컨텍스트가 유지되어 배경을 다시 설명할 필요가 없다.
- **`worker-start --terminal`로 재사용한다.** 정본이 정착 후 재사용에 지정한 경로이고, **cleanup 소유권이 새 Dispatch로 넘어가** 감독이 끊기지 않는다. `dispatch --inject`로 보내면 그 순간부터 비감독이 된다.
- `--terminal`은 `--model`/`--effort`와 함께 쓸 수 없다. 터미널이 이미 그 모델로 떠 있으므로 문제되지 않는다.
- `--parent`로 원래 태스크에 묶으면 수정 라운드가 DAG에 기록된다.
- **조치가 필요 없는 단순 안내**라면 Task를 만들지 말고 `orca terminal send --terminal <handle> --text "..." --enter` 로 직접 보낸다.

**구현 커밋은 (f)에서 이미 만들어져 있다.** 아래 분기는 그 커밋을 만들지 여부가 아니라, 리뷰 리포트를 커밋할지와 다음 라운드를 열지를 정한다.

심각도 분기:

| 조건 | 행동 |
|---|---|
| `SPEC_VIOLATION`이 1건이라도 있음 | 리뷰 리포트를 커밋하고 **즉시 Opus 에스컬레이션. 진행자가 판단하지 않는다.** 명세를 쓴 주체만 명세 위반 주장의 옳고 그름을 가릴 수 있다. 구현 커밋은 이미 있으므로 보고에 브랜치명과 커밋 목록을 포함한다 — 사람/Opus가 우선 그 커밋을 diff로 직접 볼 수 있다 |
| `BLOCKER` 또는 `MAJOR` 있음 | 리뷰 리포트를 커밋하고 **새 Task + 새 Dispatch**로 수정 라운드 (위 참조). 기존 dispatch로는 보낼 수 없다. 수정 결과는 기존 커밋을 amend하지 않고 **새 커밋**으로 쌓는다 |
| `MINOR`만 있음 | 리뷰 리포트만 커밋하고 수정을 요구하지 않는다 (핑퐁 방지) |
| `verdict: "pass"` | 리뷰 리포트를 커밋하고 성공 종료로 진행 |

## (h) 에스컬레이션과 포기

| 트리거 | 행동 |
|---|---|
| `SPEC_VIOLATION` 1회 | Opus |
| 같은 지적이 리뷰에서 2회 반복 | Opus (구현자로는 못 고침) |
| 워커가 `escalation` 발신 | Opus |
| 리뷰 라운드 3회 초과 | Opus |
| 총 라운드 5회 초과 | **사람**, 태스크 중단 |
| 같은 Task의 기동 실패 2회 | **사람**, 재시도 금지 |
| 무응답 판정 (e) | **사람** |

### 시도와 라운드를 구분한다

용어는 `CONTEXT.md`가 정본이다. 셋을 섞으면 예산이 엉뚱하게 깎인다.

| 용어 | 뜻 | 세는 법 (세션 폐기 후에도 남는 곳) |
|---|---|---|
| **기동 실패** | 워커가 태스크 프롬프트를 받기 전에 실패한 것. Orca가 보고한 실패(`agent_readiness`, `agent_prompt_blocked` 등)와 (d)의 **전달 확인** 실패를 모두 포함한다. **라운드가 아니다** | Orca Task의 실패 이력 |
| **구현 라운드** | 게이트를 통과해 커밋으로 남은 구현 한 번 | `git log <base>..HEAD`의 `Implemented-by:` 트레일러 커밋 수 |
| **리뷰 라운드** | 리뷰 리포트 하나 | `.ai/reviews/T-NNN.r*.json` 파일 개수 |
| **총 라운드** | 구현 라운드 + 리뷰 라운드 | 위 둘의 합 |

- **기동 실패는 2회에서 멈춘다.** Orca는 같은 Task가 3회 연속 실패하면 circuit-break한다. 2회째에 재시도하면 마지막 기회를 원인 모른 채 쓰게 된다(T-004에서 구현·리뷰 Task 둘 다 그 직전까지 갔다).
  원인을 찾아 해소했다면 기존 Task를 포기하고 **새 Task**로 다시 시작한다 — 재시도가 아니라 재출발이다. 재출발 전에 Task 밖에서 `terminal create` → `tui-idle`로 준비 감지가 통과하는지 먼저 확인한다.
- 기동 실패는 환경 문제이고 구현자의 실력과 무관하므로 라운드 예산을 깎지 않는다.
- "같은 지적이 2회 반복"은 **직전 라운드와 이번 라운드**(`r(N-1)`과 `rN`)의 findings를 `file` + `summary` 기준으로 비교해 판정한다

**"Opus 에스컬레이션"의 실제 행위** — 진행 세션은 스스로 판단하지 않고 다음을 한다:

1. **decision gate를 만든다.** 판단을 산문이 아니라 Orca 상태로 남기는 단계다.

   ```bash
   orca orchestration gate-create --task <task_id> \
     --question "T-NNN: 리뷰어가 SPEC_VIOLATION 주장. <한 줄 요약>. 리뷰: .ai/reviews/T-NNN.rN.json" \
     --options '["spec을 고친다","구현을 고친다","리뷰 지적을 기각한다"]' --json
   ```

   - 정본이 게이트를 허용하는 조건이 *"coordinator-owned Task-DAG decision"* 이고, SPEC_VIOLATION 판정이 정확히 그것이다. 워커의 `ask`에 답하려고 게이트를 만드는 것은 금지다.
   - **선택지 열거는 진행자가 해도 된다.** 기계적 작업이고, **선택**은 설계 세션이 `gate-resolve`로 한다. 판단 권한은 그대로 분리된다.
   - 설계 세션은 `orca orchestration gate-list --task <task_id> --json`으로 이 게이트를 찾고 `gate-resolve --id <gate_id> --resolution "<선택>"`으로 닫는다.
   - `--options`의 JSON 배열은 **셸 인용 규칙을 따른다.** PowerShell이나 `cmd.exe`에 POSIX 홑따옴표를 그대로 옮기지 않는다.
   - 게이트 명령은 Orca 터미널 안에서만 동작한다(밖에서는 `no_active_sender_terminal`). 필요하면 `--from <handle>`을 준다.
   - **아직 미검증**: `worker_done`으로 이미 정착한 Task에 게이트가 걸리는지 확인되지 않았다. 거부되면 게이트를 **리뷰 워커 dispatch 전에 미리** 만들어 두고 결과에 따라 `gate-resolve`하는 형태로 바꾼다.
2. **`orca orchestration worker-retain --dispatch <dispatch_id> --json`으로 워커를 보존한다.** 정착한 dispatch **전부**(구현·리뷰)에 대해 각각 실행한다 — 하나라도 빠지면 `reclaimable`로 남는다.
   Opus가 터미널의 마지막 출력을 봐야 판단이 서는 경우가 있고, 닫으면 그 증거가 사라진다 — (i)의 「워커 정리」 표 참조.
3. 사용자에게 **Run ID, Task ID, 에스컬레이션 사유, 관련 리뷰 파일 경로, 브랜치명과 커밋 목록**을 보고한다.
   구현 커밋은 (f)에서 이미 만들어져 있으므로 워크트리를 뒤질 필요 없이 `git log --oneline <base>..HEAD`로 바로 확인할 수 있다
4. 세션을 종료한다. 사람이 Opus 설계 세션을 열어 `gate-list`로 게이트를 찾고, spec을 고치거나 커밋을 직접 리뷰해 필요하면 새 커밋으로 고친 뒤 `gate-resolve`로 닫고 새 라운드를 시작한다

**"사람 호출"의 실제 행위** — 위와 같되, 워커 터미널을 닫지 않고 남긴다:

- `orca orchestration worker-retain --dispatch <dispatch_id> --json`
- 이유: 무응답이나 예상 밖 프롬프트는 사람이 터미널 화면을 직접 봐야 원인을 알 수 있다. 닫으면 증거가 사라진다.

## (i) 성공 종료

- 게이트 통과와 리뷰 `pass`를 확인한다.
- **자동 머지 금지.** 이유: 머지는 되돌리기 어려운 행위이고, 진행자(Sonnet)의 판단으로 사람의 최종 확인을 대체할 근거가 없다. 아래 어느 경로든 **머지 자체는 사람이 한다.**
- **구현 커밋은 (f)에서 이미 만들어졌다.** 여기서는 (g)에서 남긴 리뷰 리포트 커밋이 있는지만 확인한다.
- **커밋은 주체별로 나눈다.** 하네스 설정 / spec(설계자) / 구현(구현자) / 리뷰 리포트(리뷰어)를 각각 별도 커밋으로 남기고, 커밋 메시지에 어느 모델이 만들었는지 적는다. 나중에 `git log`만 보고 파이프라인의 어느 단계가 무엇을 만들었는지 가릴 수 있어야 한다.
- 사람이 직접 리뷰하는 단계(경로 B의 로컬 머지 전, 또는 경로 A의 PR 리뷰)에서 수정이 필요하면 그건 **추가 커밋**으로 처리한다. 이미 만든 커밋을 되돌리거나 amend할 필요 없다.

### 워커 정리 — 세션을 폐기하기 전에 반드시

Orca는 정착(settle)된 워커마다 **재사용 / `worker-retain` / `worker-release` 중 정확히 하나**를 요구하고,
`reclaimable`이 남은 채로 코디네이터 턴을 끝내지 말라고 못박는다.
진행 세션은 태스크마다 폐기되므로, **여기서 닫지 않으면 회수를 책임질 주체가 아예 사라진다.**

relay의 세 갈래 출구에 그 "정확히 하나"를 대응시키면 이렇게 된다:

| 출구 | 구현 워커 (agy) | 리뷰 워커 (codex) |
|---|---|---|
| 성공 종료 (i) | `worker-release` + 터미널 close + `trustedWorkspaces` 해제 | `worker-release` |
| 수정 라운드 (g의 `BLOCKER`/`MAJOR`) | **재사용** — 닫지 않는다. 같은 handle로 새 dispatch를 건다 | `worker-release`. 다음 리뷰 라운드는 새 워커로 띄운다 — 이전 리뷰의 맥락에 끌려가지 않게 |
| Opus 에스컬레이션 / 사람 호출 (h) | `worker-retain` — 증거를 남긴다 | `worker-retain` |

성공 종료에서만 구현 워커를 해제한다:

```bash
# 구현·리뷰 워커 둘 다 worker-start 로 감독했으므로 둘 다 release 대상이다
orca orchestration worker-release --dispatch <impl_dispatch_id> --json
orca orchestration worker-release --dispatch <review_dispatch_id> --json

# 구현 터미널은 (d)에서 직접 만든 것이라 release 가 닫지 않을 수 있다 — 닫혔는지 보고 남아 있으면 닫는다
orca terminal show --terminal <impl_handle> --json
orca terminal close --terminal <impl_handle> --json

# 남은 것이 없는지 확인한 뒤에 세션을 끝낸다
orca orchestration worker-list --run <run_id> --terminal-state reclaimable --json
```

- **`release`가 불확실할 때 그 대체로 `terminal close`를 쓰지 않는다.** 정본이 명시적으로 금지하며, release 실패는 자체 recovery receipt를 따른다.
  위의 `terminal close`는 대체가 아니다 — release가 **성공한 뒤**, 우리가 직접 만든 터미널을 만든 쪽이 정리하는 것이다.
  (**미검증**: 정본상 미리 존재하던 터미널은 release 후 `retained`로 남는다고 읽히지만 실측 전이다. 확인되면 이 주석을 고친다.)
- **증거 보존을 이유로 워커를 살려두지 않는다.** 정본: *"Do not leave it live only to inspect output; archived output remains available through `worker-read`."* release 후에도 `worker-read`로 산출물을 읽을 수 있다.

**그리고 `trustedWorkspaces`에서 그 워크트리 경로를 지운다.** (d) 2번이 추가한 항목이고, 지우는 단계가 없으면 단조 증가한다.
실측: 항목 16개 중 **5개가 이미 삭제된 relay 워크트리**였다. 워크트리 경로는 태스크명으로 재사용되므로,
죽은 항목이 남아 있으면 **미래의 다른 워크트리를 미리 신뢰하게 만든다.**

```bash
python - "<worktree path>" <<'PY'
import json, sys, pathlib
p = pathlib.Path.home() / ".gemini/antigravity-cli/settings.json"
s = json.loads(p.read_text(encoding="utf-8"))
ws = s.get("trustedWorkspaces", [])
target = sys.argv[1].replace("/", "\\")
if target in ws:
    ws.remove(target)
    p.write_text(json.dumps(s, ensure_ascii=False, indent=2), encoding="utf-8")
    print("removed:", target)
else:
    print("not present:", target)
PY
```

### 경로 A — 리뷰어가 따로 있는 저장소: PR

GitHub 리모트가 있고 다른 사람이 머지를 승인하는 경우:

```bash
git -C <worktree> push -u origin HEAD
gh pr create --head <branch> --base main \
  --title "T-NNN: <제목>" \
  --body "spec: .ai/specs/T-NNN-<슬러그>.md
review: .ai/reviews/T-NNN.rN.json
gate: <실행한 게이트 명령> — 통과"
```

### 경로 B — 저장소 오너가 직접 머지: 로컬 머지

오너 단독 저장소에서는 PR이 불필요한 왕복이다. 이때 진행 세션은 **브랜치와 커밋까지만** 만들고 멈춘다.

```bash
# 진행 세션은 여기까지만 한다: 브랜치명과 커밋 목록을 사용자에게 보고
git -C <worktree> log --oneline <base>..HEAD

# 아래는 사람이 실행한다 — 진행 세션이 대신 하지 않는다
git -C <repo> merge --no-ff <branch> -m "Merge branch '<branch>'"
```

`--no-ff`를 쓰는 이유: 머지 커밋이 남아야 한 태스크의 커밋 묶음이 이력에서 하나의 단위로 보인다. fast-forward하면 파이프라인 산출물이 main의 다른 커밋들 사이에 흩어진다.

**머지 후 게이트를 한 번 더 돌린다.** 브랜치에서 통과했어도 main과 합쳐진 뒤 깨질 수 있다.
단 **의존성 매니페스트나 lockfile이 바뀐 머지였다면 먼저 의존성을 동기화한다** (`bun install` 등). 안 하면 갱신된 매니페스트와 낡은 `node_modules`가 어긋나 실재하지 않는 오류가 나온다 — (f)의 3번 참조.

### 공통

- 리모트가 없으면 브랜치만 남기고 사용자에게 브랜치명을 보고한다.
- 어느 경로든 **진행 세션은 머지하지 않고 폐기한다.**

## (j) 컨텍스트 위생 규범

진행 세션이 반드시 지킬 것:

1. **`orca ... --json` 출력을 원본 그대로 받지 말 것.** 항상 필요한 필드만 추출해서 읽는다. orca의 JSON 응답은 크고, 매 턴 재전송되어 비용이 누적된다.
2. **태스크 하나가 끝나면 세션을 폐기한다.** 여러 태스크를 한 세션에서 돌리면 컨텍스트가 선형 누적되고, 재전송 비용은 그 누적의 합이라 제곱으로 늘어난다.
3. 태스크 상태는 `task-list --ready`로 매번 조회한다. 컨텍스트에 들고 있지 않는다.

## (k) 병렬 실행 정책

현재는 **순차 실행**이다. 단 `task-create --deps`로 DAG는 처음부터 정의한다 —
나중에 병렬로 전환할 때 태스크 정의를 고치지 않고 실행 정책만 바꾸면 되게 하기 위해서다.
승격 기준은 **연속 5개 태스크가 에스컬레이션 없이 통과**하는 것이다.
의존 사슬은 3~4단계를 넘기지 않는다(Orca 가이드 권고).
