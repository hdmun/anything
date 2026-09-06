---
name: relay
description: Orca orchestration 위에서 설계자(Opus)·진행자(Sonnet)·구현자(agy)·리뷰어(codex) 4역할 파이프라인을 굴릴 때 사용한다. spec 작성부터 워커 dispatch, 게이트 재검증, 리뷰 심각도 분기, PR 생성까지를 다룬다.
---

# relay

`relay`는 3개 AI 코딩 에이전트를 Orca orchestration 위에서 연결하는 파이프라인의 코디네이터 스킬이다.

## 역할과 모델

| 역할 | 실행 주체 | 모델 / effort | Orca에서의 위치 |
|---|---|---|---|
| 설계자 | Claude Code | Opus / high | 코디네이터 자신 (워커 아님) |
| 진행자 | Claude Code | Sonnet 5 / medium | Run에 재바인딩, 태스크당 세션 폐기 |
| 구현자 | agy (Antigravity CLI) | `gemini-3.8-flash-low` | supervised worker |
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
[진행 Sonnet·med] run-use → 워커 부트스트랩 → dispatch
                          ↓
[구현 agy·low]    구현 + 자체 게이트 루프
                          ↓
[진행]            게이트 독립 재검증
                          ↓
[리뷰 codex·high] .ai/reviews/T-NNN.rN.json 작성
                          ↓
[진행]            스키마 검증 → 심각도 분기 → PR 생성 → 세션 폐기
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
3. `orca orchestration run-create --objective "<목표>" --json`
4. `orca orchestration task-create --spec "<한 줄 요약 + spec 파일 경로>" [--deps <json_array>] --json`
   - **spec 전문을 `--spec`에 넣지 말 것.** 정본은 git 파일이고 `--spec`은 요약과 경로만 담는다.
   - 이유 세 가지: (1) 리뷰어가 SPEC_VIOLATION을 판정하려면 git에서 spec을 읽어야 한다 (2) spec 수정 이력이 diff로 남아야 한다 (3) Windows 명령행 길이 제한에 걸린다.
   - 의존 관계가 있으면 `--deps`로 DAG를 만든다. 실행은 순차지만 DAG는 처음부터 정의한다.
5. 세션 종료 — Run ID를 사용자에게 알려준다.

## (c) 진행 세션 절차

1. `orca orchestration run-use --id <run_id> --json`
2. `orca orchestration task-list --ready --json` 로 다음 태스크를 꺼낸다. **태스크 상태를 컨텍스트에 들고 있지 말고 매번 Orca에 물어본다** (외부 메모리로 사용).
3. 워커 부트스트랩 — (d)
4. dispatch 후 대기 — (e)
5. 게이트 독립 재검증 — (f)
6. 리뷰 워커 dispatch, 리뷰 JSON 검증, 심각도 분기 — (g)
7. PR 생성 후 세션 폐기 — (i), (j)

## (d) 워커 부트스트랩

**구현 워커(agy)**

1. `orca worktree create --repo <sel> --name T-NNN --base-branch main --json` 으로 worktree 경로를 확보한다.
   - **`--base-branch`를 반드시 명시한다.** 생략하면 repo의 `defaultBaseRef`를 쓰는데, 그 값이 `null`인 저장소에서는 엉뚱한 지점에서 분기된다. 실측 사례: `defaultBaseRef: null`인 저장소에서 최신 `main`이 아니라 **최초 커밋**에서 분기되어, 워크트리에 소스가 거의 없는 상태로 만들어졌다.
   - 만든 직후 `git -C <worktree> log --oneline -1`로 base가 의도한 커밋인지 확인한다. 어긋났으면 `git -C <worktree> reset --hard <base>`로 맞춘다(추적되지 않은 파일은 보존된다).
2. **`~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces` 배열에 그 worktree 경로를 추가한다.**
   - 이유: 등록하지 않으면 agy가 "Do you trust the contents of this project?" 프롬프트에서 멈춘다. Orca가 이를 `agentWait{reason:"codex-trust-workspace"}`로 감지해 **`dispatch`를 `agent_prompt_blocked`로 거부한다.** 실측으로 확인된 동작이다.
   - 더 나쁜 점: 사람이 프롬프트를 해소해도 **스크롤백에 남은 텍스트 때문에 감지가 풀리지 않아 dispatch가 계속 막힌다.** 사전 등록이 유일하게 깨끗한 해법이다.
   - `worktree create`는 경로를 슬래시(`C:/Users/...`)로 반환하지만 `trustedWorkspaces`의 기존 항목은 백슬래시(`C:\Users\...`)다. **반드시 백슬래시로 정규화해서 넣는다.**

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

3. `orca terminal create --worktree id:<wt> --title "T-NNN-impl" --command "agy --model gemini-3.8-flash-low" --json`
   - `--dangerously-skip-permissions`나 `--sandbox`를 **쓰지 않는다.** 실측 결과 기본 권한만으로 파일 편집과 셸 실행이 프롬프트 없이 완주했다. 최소 권한을 유지한다.
4. `orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 90000 --json`
   - **주의: agy에 대해 `tui-idle`은 신뢰할 수 없다.** 실제로 idle인데 `satisfied: false`를 반환하는 오탐이 관측되었다(`agentIdentity`가 `null`이라 후크 기반 판정이 없기 때문). 이 대기는 참고용이며, `satisfied: false`여도 다음 단계로 진행한다.
5. `orca orchestration dispatch --task <id> --to <handle> --inject --json`

**dispatch ID 확보** — 이후 `send --to dispatch:<id>`에 필요하다.
`dispatch --inject`의 응답은 `result.dispatch.id`에 담기지만, `worker-start`의 응답은 `stage: "input_accepted"`만 오고 dispatch가 비어 있는 경우가 있다.
**응답에서 못 찾으면 `orca orchestration dispatch-show --task <task_id> --json`으로 조회한다.** 추측하지 말 것.

**Git Bash 주의** — `terminal send --text "/clear"` 처럼 `/`로 시작하는 인자는 Git Bash가 `C:/Program Files/Git/clear`로 경로 변환한다. `MSYS_NO_PATHCONV=1`을 앞에 붙인다.

**리뷰 워커(codex)** — Orca 1급 에이전트라 훨씬 간단하다:

- `orca orchestration worker-start --task <id> --worktree id:<구현과 같은 worktree> --agent codex --model gpt-5.6-luna --effort high --json`
- **구현 워커와 같은 worktree를 쓴다.** 파이프라인이 순차라 충돌이 없고, `codex review --uncommitted`로 미커밋 변경을 그대로 볼 수 있어 구현자에게 커밋을 강제하지 않아도 된다.

### `worker-start --agent antigravity`를 쓰지 않는 이유

`antigravity`는 Orca가 아는 에이전트 id가 맞다. `worker-start --agent antigravity`는 정상 수락되고, 수동 기동과 달리 터미널에 `agentIdentity: antigravity`도 제대로 붙는다. 그런데도 위의 수동 경로를 기본으로 쓰는 이유는 실측된 제약 세 가지 때문이다.

| 관측 | 결과 |
|---|---|
| `launch.effective`가 `{"model": null, "effort": null}` | **`--model`이 전달되지 않아 기본 모델(Gemini 3.8 Flash Medium)로 뜬다.** 우리가 정한 `low`를 쓸 수 없다 |
| 새 worktree에서 트러스트 프롬프트에 그대로 멈춤 | `trustedWorkspaces` 사전 등록은 **이 경로에서도 필수**다 |
| 멈춰 있는데 `agentWait`가 `null` | **오탐.** 수동 기동 경로에서는 `codex-trust-workspace`로 정확히 잡혔다 |

**기본 모델(Medium)로 충분한 태스크라면 `--agent antigravity`가 더 간단하다.** 모델을 지정해야 하면 수동 경로를 쓴다. 어느 쪽이든 2단계(`trustedWorkspaces` 등록)는 건너뛸 수 없다.

## (e) 대기와 무응답 판정

- `orca orchestration check --wait --types worker_done,escalation,question --timeout-ms 600000 --json`
- **stdout만 파이프할 것.** `--wait` 중 stderr로 keepalive(`{"_keepalive":true}`)가 나오므로 `2>&1`로 합치면 파서가 깨진다.
- `question`이 오면 `orca orchestration reply --id <msg_id> --body <답> --json` 으로 답하고 다시 대기한다.

창이 빈손으로 돌아왔을 때의 판정:

| 관측 | 해석 | 행동 |
|---|---|---|
| `agentWait` ≠ null | 프롬프트에 멈춤 | **사람 호출** (자동 응답 금지) |
| `lastOutputAt`이 기준시간 이내 | 작업 중 | 창 재개 |
| `lastOutputAt`이 기준시간 이상 정지 | 조용히 멈춤 | **사람 호출** |

기준시간은 구현 워커 **5분**, 리뷰 워커 **10분**이다.

**`agentWait`는 양성 신호로만 믿는다.** 값이 있으면 실제로 멈춘 것이지만, `null`은 안 멈췄다는 증거가 아니다.

- Orca 문서: `absent`는 "안 기다린다"가 아니라 "확인하지 못했다"라는 뜻이다.
- 실측: `worker-start --agent antigravity`로 띄운 워커가 **트러스트 프롬프트에 멈춘 상태에서 `agentWait: null`을 반환했다.** 같은 상황을 수동 기동 경로에서는 정확히 잡았다. 즉 기동 방식에 따라 오탐이 난다.

따라서 **`lastOutputAt`이 1차 신호**이고 `agentWait`·`tui-idle`·heartbeat는 보조다. 셋 다 없다고 해서 "정상 작업 중"이라고 결론 내리지 않는다.

**프롬프트 자동 응답은 금지한다.** `trustedWorkspaces` 사전 등록으로 알려진 프롬프트는 이미 제거했으므로, 남은 프롬프트는 예상 밖의 것이고 사람이 봐야 한다.

## (f) 게이트 독립 재검증

워커가 자체 루프로 게이트를 돌리지만, `worker_done` 수신 후 **진행자가 같은 게이트를 직접 다시 실행한다.**

- 이유 1: 워커의 자체 보고를 신뢰하되 검증한다.
- 이유 2: 셸 명령이라 LLM 토큰을 쓰지 않는다 — 사실상 공짜다.
- 이유 3: **게이트를 통과하지 못한 코드를 리뷰 워커에게 넘기면 codex 토큰이 낭비된다.**

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

orca orchestration dispatch --task <새 task_id> --to <워커 터미널 handle> --inject --json
```

- **워커 터미널은 살아 있으므로 같은 handle을 재사용한다.** 세션 컨텍스트가 유지되어 배경을 다시 설명할 필요가 없다.
- `--parent`로 원래 태스크에 묶으면 수정 라운드가 DAG에 기록된다.
- **조치가 필요 없는 단순 안내**라면 Task를 만들지 말고 `orca terminal send --terminal <handle> --text "..." --enter` 로 직접 보낸다.

심각도 분기:

| 조건 | 행동 |
|---|---|
| `SPEC_VIOLATION`이 1건이라도 있음 | **즉시 Opus 에스컬레이션. 진행자가 판단하지 않는다.** 명세를 쓴 주체만 명세 위반 주장의 옳고 그름을 가릴 수 있다 |
| `BLOCKER` 또는 `MAJOR` 있음 | **새 Task + 새 Dispatch**로 수정 라운드 (위 참조). 기존 dispatch로는 보낼 수 없다 |
| `MINOR`만 있음 | 기록만 하고 수정을 요구하지 않는다 (핑퐁 방지) |
| `verdict: "pass"` | 성공 종료로 진행 |

## (h) 에스컬레이션과 포기

| 트리거 | 행동 |
|---|---|
| `SPEC_VIOLATION` 1회 | Opus |
| 같은 지적이 리뷰에서 2회 반복 | Opus (구현자로는 못 고침) |
| 워커가 `escalation` 발신 | Opus |
| 리뷰 라운드 3회 초과 | Opus |
| 총 라운드 5회 초과 | **사람**, 태스크 중단 |
| 무응답 판정 (e) | **사람** |

**라운드 수는 파일로 센다.** 진행 세션은 폐기되므로 카운터를 컨텍스트에 둘 수 없다.

- 리뷰 라운드 수 = `.ai/reviews/T-NNN.r*.json` 파일 개수
- "같은 지적이 2회 반복"은 `T-NNN.r1.json`과 `r2.json`의 findings를 `file` + `summary` 기준으로 비교해 판정한다

**"Opus 에스컬레이션"의 실제 행위** — 진행 세션은 스스로 판단하지 않고 다음을 한다:

1. `orca orchestration task-update --id <task_id> --status <blocked 상태값> --json`
   (유효한 상태값은 `--help`와 `task-list` 출력으로 확인한다. 추측해서 넣지 말 것)
2. 사용자에게 **Run ID, Task ID, 에스컬레이션 사유, 관련 리뷰 파일 경로**를 보고한다
3. 세션을 종료한다. 사람이 Opus 설계 세션을 열어 spec을 고치고 새 라운드를 시작한다

**"사람 호출"의 실제 행위** — 위와 같되, 워커 터미널을 닫지 않고 남긴다:

- `orca orchestration worker-retain --dispatch <dispatch_id> --json`
- 이유: 무응답이나 예상 밖 프롬프트는 사람이 터미널 화면을 직접 봐야 원인을 알 수 있다. 닫으면 증거가 사라진다.

## (i) 성공 종료

- 게이트 통과와 리뷰 `pass`를 확인한다.
- **자동 머지 금지.** 이유: 머지는 되돌리기 어려운 행위이고, 진행자(Sonnet)의 판단으로 사람의 최종 확인을 대체할 근거가 없다.
- GitHub 리모트가 있으면 PR까지 만든다:

```bash
git -C <worktree> push -u origin HEAD
gh pr create --head <branch> --base main \
  --title "T-NNN: <제목>" \
  --body "spec: .ai/specs/T-NNN-<슬러그>.md
review: .ai/reviews/T-NNN.rN.json
gate: <실행한 게이트 명령> — 통과"
```

- 리모트가 없으면 브랜치만 남기고 사용자에게 브랜치명을 보고한다.
- 어느 경우든 **머지하지 않고 세션을 폐기한다.**

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
