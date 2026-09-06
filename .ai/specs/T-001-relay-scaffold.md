# T-001: relay 스킬 골격 작성

## 배경 (구현자는 이전 대화를 모른다 — 여기에 다 적는다)

`relay`는 **3개 AI 코딩 에이전트를 Orca orchestration 위에서 연결하는 파이프라인**의 코디네이터 스킬이다.
Claude Code 스킬 형식(`SKILL.md` + `references/`)으로 만든다.

파이프라인 구성은 다음과 같이 **이미 확정되었다**. 재설계하지 말고 그대로 문서화할 것.

### 역할과 모델

| 역할 | 실행 주체 | 모델 / effort | Orca에서의 위치 |
|---|---|---|---|
| 설계자 | Claude Code | Opus / high | 코디네이터 자신 (워커 아님) |
| 진행자 | Claude Code | Sonnet 5 / medium | Run에 재바인딩, 태스크당 세션 폐기 |
| 구현자 | agy (Antigravity CLI) | `gemini-3.8-flash-low` | supervised worker |
| 리뷰어 | codex | `gpt-5.6-luna` / high | supervised worker |

### 왜 세션을 둘로 나누는가

Claude Code는 매 턴 전체 컨텍스트를 재전송하므로 비용은 (컨텍스트 크기 × 턴 수)에 비례한다.
코디네이터 루프는 태스크당 10~20턴인데 판단 함량이 거의 없다(대부분 조건 분기).
반면 설계·명세·중재는 턴 수가 적고 판단 함량이 최대다.
따라서 잦고 긴 구간은 Sonnet에, 드물고 짧은 구간은 Opus에 배치한다.
Orca가 상태(Run/Task/Dispatch)를 소유하므로 세션을 버려도 잃는 것이 없다 — `run-use`로 재바인딩한다.

### 파이프라인 흐름

```
[설계 Opus·high]  /grill-with-docs  (발동 기준은 아래)
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
[리뷰 codex·high] .ai/reviews/T-NNN.json 작성
                          ↓
[진행]            스키마 검증 → 심각도 분기 → PR 생성 → 세션 폐기
```

## 범위 밖 (건드리지 말 것)

- `~/.claude/`, `~/.claude-max/` 등 홈 디렉터리 설정 — 설치는 별도 단계이며 이 태스크가 아니다
- `.ai/roles/*.md` (구현자/리뷰어 규범) — 다음 태스크(T-002)에서 만든다
- 대상 repo(`poker-server`)의 어떤 파일도 — 이 태스크는 `scripts` repo 안에서만 작업한다
- 아래 "변경 대상 파일" 목록 밖의 파일 생성/수정 금지

## 변경 대상 파일

- `skills/relay/SKILL.md` — 신규
- `skills/relay/references/spec-template.md` — 신규
- `skills/relay/references/review-schema.json` — 신규

## 파일별 내용 요구사항

### 1) `skills/relay/SKILL.md`

frontmatter는 정확히 이 형식으로 한다 (다른 키 추가 금지):

```
---
name: relay
description: <한 줄. 언제 이 스킬을 쓰는지가 드러나야 함>
---
```

본문에 **반드시** 포함할 절은 아래 (a)~(k) 열한 개다.

#### (a) 두 세션의 구분

설계 세션과 진행 세션이 각각 무엇을 하고 어디서 끝나는지.
읽는 사람이 "지금 나는 어느 세션인가"를 즉시 판단할 수 있어야 한다.

#### (b) 설계 세션 절차

1. `grill-with-docs` 발동 기준: **새 개념/용어가 등장하거나, 되돌리기 어려운 결정이 포함되거나, spec을 쓰다 두 번 이상 막힐 때.** 그 외에는 바로 spec을 쓴다. 오탈자 수정 같은 것에까지 grilling을 걸지 않는다.
2. `.ai/specs/T-NNN.md` 작성 — `references/spec-template.md`를 따른다.
3. `orca orchestration run-create --objective "<목표>" --json`
4. `orca orchestration task-create --spec "<한 줄 요약 + spec 파일 경로>" [--deps <json_array>] --json`
   - **spec 전문을 `--spec`에 넣지 말 것.** 정본은 git 파일이고 `--spec`은 요약과 경로만 담는다.
   - 이유 세 가지: (1) 리뷰어가 SPEC_VIOLATION을 판정하려면 git에서 spec을 읽어야 한다 (2) spec 수정 이력이 diff로 남아야 한다 (3) Windows 명령행 길이 제한에 걸린다.
   - 의존 관계가 있으면 `--deps`로 DAG를 만든다. 실행은 순차지만 DAG는 처음부터 정의한다.
5. 세션 종료 — Run ID를 사용자에게 알려준다.

#### (c) 진행 세션 절차

1. `orca orchestration run-use --id <run_id> --json`
2. `orca orchestration task-list --ready --json` 로 다음 태스크를 꺼낸다. **태스크 상태를 컨텍스트에 들고 있지 말고 매번 Orca에 물어본다** (외부 메모리로 사용).
3. 워커 부트스트랩 — (d)
4. dispatch 후 대기 — (e)
5. 게이트 독립 재검증 — (f)
6. 리뷰 워커 dispatch, 리뷰 JSON 검증, 심각도 분기 — (g)
7. PR 생성 후 세션 폐기 — (i), (j)

#### (d) 워커 부트스트랩

**구현 워커(agy)** — 순서와 이유를 함께 적을 것:

1. `orca worktree create --repo <sel> --name T-NNN --json` 으로 worktree 경로를 확보한다.
2. **`~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces` 배열에 그 worktree 경로를 추가한다.**
   - 이유: 등록하지 않으면 agy가 "Do you trust the contents of this project?" 프롬프트에서 멈춘다. Orca가 이를 `agentWait{reason:"codex-trust-workspace"}`로 감지해 **`dispatch`를 `agent_prompt_blocked`로 거부한다.** 실측으로 확인된 동작이다.
   - 더 나쁜 점: 사람이 프롬프트를 해소해도 **스크롤백에 남은 텍스트 때문에 감지가 풀리지 않아 dispatch가 계속 막힌다.** 사전 등록이 유일하게 깨끗한 해법이다.
3. `orca terminal create --worktree id:<wt> --title "T-NNN-impl" --command "agy --model gemini-3.8-flash-low" --json`
   - `--dangerously-skip-permissions`나 `--sandbox`를 **쓰지 않는다.** 실측 결과 기본 권한만으로 파일 편집과 셸 실행이 프롬프트 없이 완주했다. 최소 권한을 유지한다.
4. `orca terminal wait --terminal <handle> --for tui-idle --timeout-ms 90000 --json`
   - **주의: agy에 대해 `tui-idle`은 신뢰할 수 없다.** 실제로 idle인데 `satisfied: false`를 반환하는 오탐이 관측되었다(`agentIdentity`가 `null`이라 후크 기반 판정이 없기 때문). 이 대기는 참고용이며, `satisfied: false`여도 다음 단계로 진행한다.
5. `orca orchestration dispatch --task <id> --to <handle> --inject --json`

**리뷰 워커(codex)** — Orca 1급 에이전트라 훨씬 간단하다:

- `orca orchestration worker-start --task <id> --worktree id:<구현과 같은 worktree> --agent codex --model gpt-5.6-luna --effort high --json`
- **구현 워커와 같은 worktree를 쓴다.** 파이프라인이 순차라 충돌이 없고, `codex review --uncommitted`로 미커밋 변경을 그대로 볼 수 있어 구현자에게 커밋을 강제하지 않아도 된다.

**확인 항목으로 남길 것**: Orca 터미널 목록에서 `agentIdentity: antigravity`가 관측된 사례가 있다. `worker-start --agent antigravity`가 유효하다면 위 3~5단계를 대체할 수 있다. 첫 실전 태스크에서 검증한다.

#### (e) 대기와 무응답 판정

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
`tui-idle`과 heartbeat는 **보조 신호로만** 쓴다 — 없다고 해서 결론을 내리지 않는다.
Orca 문서에 `agentWait`의 `absent`는 "안 기다린다"가 아니라 "확인하지 못했다"라는 뜻이라고 명시돼 있다.

**프롬프트 자동 응답은 금지한다.** `trustedWorkspaces` 사전 등록으로 알려진 프롬프트는 이미 제거했으므로, 남은 프롬프트는 예상 밖의 것이고 사람이 봐야 한다.

#### (f) 게이트 독립 재검증

워커가 자체 루프로 게이트를 돌리지만, `worker_done` 수신 후 **진행자가 같은 게이트를 직접 다시 실행한다.**

- 이유 1: 워커의 자체 보고를 신뢰하되 검증한다.
- 이유 2: 셸 명령이라 LLM 토큰을 쓰지 않는다 — 사실상 공짜다.
- 이유 3: **게이트를 통과하지 못한 코드를 리뷰 워커에게 넘기면 codex 토큰이 낭비된다.**

게이트 명령은 repo마다 다르며 spec의 인수 조건에 명시된다.
예를 들어 Go repo라면 `go build ./... && go vet ./... && go test ./...` 이다.

#### (g) 리뷰 결과 처리

리뷰어는 `.ai/reviews/T-NNN.json`을 쓰고 `worker_done`의 `--report-path`로 경로를 넘긴다.
진행자는 `references/review-schema.json`에 맞는지 검증한다.
**형식 위반이면 `orca orchestration send --to dispatch:<id>` 로 재작성을 요구한다** — 비용은 리뷰 1회 재실행뿐이다.

심각도 분기:

| 조건 | 행동 |
|---|---|
| `SPEC_VIOLATION`이 1건이라도 있음 | **즉시 Opus 에스컬레이션. 진행자가 판단하지 않는다.** 명세를 쓴 주체만 명세 위반 주장의 옳고 그름을 가릴 수 있다 |
| `BLOCKER` 또는 `MAJOR` 있음 | 같은 dispatch에 `send`로 수정 지시 |
| `MINOR`만 있음 | 기록만 하고 수정을 요구하지 않는다 (핑퐁 방지) |
| `verdict: "pass"` | 성공 종료로 진행 |

#### (h) 에스컬레이션과 포기

| 트리거 | 행동 |
|---|---|
| `SPEC_VIOLATION` 1회 | Opus |
| 같은 지적이 리뷰에서 2회 반복 | Opus (구현자로는 못 고침) |
| 워커가 `escalation` 발신 | Opus |
| 리뷰 라운드 3회 초과 | Opus |
| 총 라운드 5회 초과 | **사람**, 태스크 중단 |
| 무응답 판정 (e) | **사람** |

#### (i) 성공 종료

- 게이트 통과와 리뷰 `pass`를 확인한다.
- **자동 머지 금지.** 브랜치를 남기고, GitHub 리모트가 있으면 `gh pr create`까지 한다.
- 이유: 머지는 되돌리기 어려운 행위이고, 진행자(Sonnet)의 판단으로 사람의 최종 확인을 대체할 근거가 없다.

#### (j) 컨텍스트 위생 규범

진행 세션이 반드시 지킬 것:

1. **`orca ... --json` 출력을 원본 그대로 받지 말 것.** 항상 필요한 필드만 추출해서 읽는다. orca의 JSON 응답은 크고, 매 턴 재전송되어 비용이 누적된다.
2. **태스크 하나가 끝나면 세션을 폐기한다.** 여러 태스크를 한 세션에서 돌리면 컨텍스트가 선형 누적되고, 재전송 비용은 그 누적의 합이라 제곱으로 늘어난다.
3. 태스크 상태는 `task-list --ready`로 매번 조회한다. 컨텍스트에 들고 있지 않는다.

#### (k) 병렬 실행 정책

현재는 **순차 실행**이다. 단 `task-create --deps`로 DAG는 처음부터 정의한다 —
나중에 병렬로 전환할 때 태스크 정의를 고치지 않고 실행 정책만 바꾸면 되게 하기 위해서다.
승격 기준은 **연속 5개 태스크가 에스컬레이션 없이 통과**하는 것이다.
의존 사슬은 3~4단계를 넘기지 않는다(Orca 가이드 권고).

### 2) `skills/relay/references/spec-template.md`

설계자가 `.ai/specs/T-NNN.md`를 쓸 때 채우는 템플릿. 마크다운 템플릿 그 자체를 담는다.
아래 절을 반드시 포함할 것:

- `# T-NNN: <제목>`
- `## 배경` — "구현자는 이전 대화를 모른다. 여기에 다 적는다"는 안내 문구를 템플릿 안에 남길 것
- `## 범위 밖 (건드리지 말 것)`
- `## 변경 대상 파일` — 파일별로 신규/수정을 구분하고, "이 목록 밖의 파일은 생성/수정 금지" 문구를 포함
- `## 시그니처` — "그대로 쓸 것, 임의 변경 금지"
- `## 동작 명세` — 정상 경로 / 엣지 케이스 / 에러 처리
- `## 기존 코드 참조` — `path/to/file.go:42` 형식으로 따라야 할 패턴을 지목
- `## 인수 조건` — 체크박스 목록. **게이트 명령을 실행 가능한 형태로 반드시 명시**
- `## 판단이 필요하면` — 아래 문구를 그대로 넣을 것:

> 스스로 판단하지 말고 `orca orchestration ask --question "<질문>" --timeout-ms 600000` 으로
> 코디네이터에게 물어보고 답을 받은 뒤 진행하세요. 파일에 메모를 남기고 중단하지 마세요.
> `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.

### 3) `skills/relay/references/review-schema.json`

JSON Schema (draft 2020-12). 리뷰 산출물의 형식을 규정한다.

규정할 문서 형태:

```
{
  "taskId": "T-001",
  "verdict": "pass" | "changes_requested",
  "findings": [
    {
      "severity": "SPEC_VIOLATION" | "BLOCKER" | "MAJOR" | "MINOR",
      "file": "internal/game/table.go",
      "line": 42,
      "summary": "한 문장",
      "repro": "입력 → 잘못된 출력",
      "specRef": "spec의 어느 항목을 위반했는지"
    }
  ]
}
```

제약 조건:

- 최상위에서 `taskId`, `verdict`, `findings`는 필수
- finding에서 `severity`, `file`, `summary`, `repro`는 필수
- **`repro` 필수가 추측성 지적을 걸러낸다** — 재현 시나리오를 쓰지 못하는 지적은 무효다
- `severity`가 `SPEC_VIOLATION`일 때는 `specRef`도 필수 (조건부 required)
- 최상위와 finding 모두 `additionalProperties: false`

## 인수 조건 (통과해야 완료)

- [ ] 세 파일이 지정한 경로에 존재한다
- [ ] `SKILL.md`의 frontmatter가 `name: relay`이고 `description`이 한 줄로 존재한다
- [ ] `SKILL.md`에 (a)~(k) 열한 개 절이 모두 있다
- [ ] `review-schema.json`이 유효한 JSON이다. 다음 명령이 `ok`를 출력한다:
      `node -e "JSON.parse(require('fs').readFileSync('skills/relay/references/review-schema.json','utf8'));console.log('ok')"`
- [ ] `review-schema.json`에 `SPEC_VIOLATION`일 때 `specRef`를 요구하는 조건부 제약이 들어 있다
- [ ] 위 표와 수치(5분/10분, 3회/5회, 연속 5개 등)가 문서에 **그대로** 반영되어 있다. 임의로 바꾸지 말 것

## 문체

- 한국어로 작성한다.
- **규칙에는 이유를 함께 적는다.** "이렇게 하라"만 있으면 나중에 읽는 사람이 예외 상황에서 판단하지 못한다.
- 표를 적극 쓴다. 산문으로 늘어놓지 않는다.

## 판단이 필요하면

스스로 판단하지 말고 `orca orchestration ask --question "<질문>" --timeout-ms 600000` 으로
코디네이터에게 물어보고 답을 받은 뒤 진행하세요. 파일에 메모를 남기고 중단하지 마세요.
`AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
