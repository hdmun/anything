# relay

[Orca](https://www.onorca.dev) orchestration 위에서 AI 코딩 에이전트 넷을 역할별로 묶어 태스크 하나를 **spec부터 머지 직전까지** 옮기는 Claude Code 플러그인.

| 역할 | 실행 주체 | 하는 일 |
|---|---|---|
| 설계자 | Claude Code · Opus | spec 작성, Run/Task 생성, SPEC_VIOLATION 중재 |
| 진행자 | Claude Code · Sonnet | 워커 기동, 대기, 게이트 재검증, 리뷰 분기, PR/브랜치 보고 |
| 구현자 | agy (Antigravity CLI) | spec을 코드로 옮기고 게이트를 통과시킨다 |
| 리뷰어 | codex | 커밋된 변경을 spec과 대조해 심각도별 JSON 리포트를 낸다 |

설계는 드물고 짧지만 판단이 무겁고, 진행은 잦고 길지만 대부분 조건 분기다. 그래서 둘을 다른 세션·다른 모델로 나눈다. 상태는 Orca(Run/Task/Dispatch)와 git이 소유하므로 진행 세션은 태스크마다 버린다.

## 준비물

1. **Orca** — `orca` CLI가 PATH에 있어야 한다. 진행 세션은 Orca 터미널 안에서 돈다.
2. **agy** — 워크트리를 `~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces`에 등록해야 한다(진행자가 기동 때 추가하고 성공 종료 때 지운다).
3. **codex** — `~/.codex/config.toml`에 아래 두 키가 필요하다. 없으면 Orca가 codex 기동을 감지하지 못하거나 업데이트 프롬프트에서 멈춘다.

   ```toml
   check_for_update_on_startup = false

   [tui]
   terminal_title = ["app-name", "activity", "project-name"]
   ```

4. **Python 3** — `/relay:init`이 역할 파일을 렌더링할 때 쓴다(표준 라이브러리만).

## 설치

마켓플레이스 소스는 이 저장소의 **로컬 폴더**다.

```bash
claude plugin marketplace add C:\Users\hdmun\scripts
claude plugin install relay@hdmun-scripts
```

설정 디렉터리를 여러 개 쓰면(`~/.claude`, `~/.claude-max`) 각각에서 설치한다.

## 사용

### 1. 저장소 준비 — `/relay:init`

relay를 쓸 저장소에서 한 번 실행한다. 워커가 읽는 역할 파일과 게이트 로그 `.gitignore` 항목을 만든다.

```
/relay:init            # 없으면 생성, 있고 다르면 거부
/relay:init --check    # 쓰지 않고 드리프트만 확인 (종료코드 1 = 드리프트)
/relay:init --force    # 템플릿으로 덮어쓰기
```

| 생성물 | 정본 |
|---|---|
| `.ai/roles/implementer.md`, `.ai/roles/reviewer.md` | 플러그인 `templates/` (공유 규범) + 저장소의 `.ai/relay-roles.json` (게이트 명령 등 고유분) |
| `.gitignore`의 `# >>> relay gate logs >>>` 블록 | `.ai/relay-roles.json`의 `gate_logs` |

역할 파일은 손으로 고치지 않는다. 공유 규범은 템플릿을, 저장소 고유분은 `.ai/relay-roles.json`을 고치고 `--force`로 다시 만든다.
워커는 `AGENTS.md`/`CLAUDE.md`의 링크를 통해서만 역할 파일에 도달하므로 링크를 걸어 둔다.

### 2. 설계 세션 (Opus)

"relay로 T-NNN 설계해줘"처럼 요청하면 `relay` 스킬이 발동한다.
`.ai/specs/T-NNN-<슬러그>.md`를 쓰고 `run-create`/`task-create`까지 한 뒤 **Run ID를 알려주고 끝난다.**

### 3. 진행 세션 (Sonnet)

새 세션에서 `/model sonnet`으로 바꾸고 "relay Run `<run_id>` 진행해줘"라고 요청한다. 태스크 하나를 끝까지 몰고 간다.

```
run-use → 워크트리·기준선 게이트 → agy 기동·전달 확인 → 대기
→ 게이트 재검증 → 구현 커밋 → 빈 diff 확인 → codex 리뷰
→ 심각도 분기 → 브랜치/PR 보고 → 워커 정리 → 세션 폐기
```

**머지는 하지 않는다.** 진행 세션은 브랜치와 커밋 목록(또는 PR)까지만 만들고, 머지는 사람이 한다.

#### 진행 세션이 멈추고 사람을 부르는 경우

| 상황 | 이유 |
|---|---|
| 같은 Task의 기동 실패 2회 | Orca는 3회째에 circuit-break한다. 원인을 해소한 뒤 새 Task로 재출발한다 |
| 워커가 프롬프트에 멈춤 / 출력 정지(구현 5분·리뷰 10분) | 자동 응답은 금지다 |
| 총 라운드 5회 초과 | 태스크를 중단한다 |
| `SPEC_VIOLATION`, 같은 지적 반복, 리뷰 라운드 3회 초과 | 사람 대신 **설계 세션(Opus)** 으로 넘긴다 — Orca decision gate로 남긴다 |

## 구조

```
plugins/relay/
  .claude-plugin/plugin.json      버전
  skills/relay/SKILL.md           설계·진행 세션 절차 (정본)
  skills/relay/references/        spec 템플릿, 리뷰 JSON 스키마
  commands/init.md                /relay:init
  scripts/render_roles.py         역할 파일 렌더러
  templates/*.md.tmpl             역할 파일 템플릿
  CONTEXT.md                      용어집 (기동 실패, 라운드, 모델 계열 …)
  docs/adr/                       구조 결정 기록
  docs/plan.md                    진행 중인 작업 계획
```

## 플러그인 고치기

1. 이 폴더의 소스를 고친다. 설치본(`~/.claude*/plugins/cache/hdmun-scripts/relay/<version>/`)은 관리 복사본이라 직접 고치지 않는다.
2. `.claude-plugin/plugin.json`의 `version`을 올린다.
3. 머지한 뒤 **main이 체크아웃된 상태에서** 설정 디렉터리마다 `claude plugin update relay`를 실행한다. 마켓플레이스 소스가 로컬 폴더라 체크아웃된 내용이 그대로 설치된다.
4. 템플릿을 바꿨다면 relay를 쓰는 저장소마다 `/relay:init --check` → `--force`. 진행 중인 태스크가 있으면 끝난 뒤에 한다 — 역할 파일 변경이 그 태스크의 diff에 섞인다.
5. 진행 중인 relay 세션은 재시작해야 새 스킬을 읽는다.

**모델 버전은 적지 않는다.** 역할에는 계열(Opus, Sonnet, codex·agy 기본 모델)만 배정하고, 실제 버전은 커밋 트레일러(`Implemented-by:`, `Reviewed-by:`)로 남는다. 새 모델이 나와도 고칠 곳이 없다.

## 알려진 한계

- 실전으로 아직 검증하지 못한 동작이 있다. 목록과 확인 계획은 [docs/plan.md](docs/plan.md)의 「미검증」에 있다.
- 실행은 순차다. DAG(`--deps`)는 처음부터 정의하되 병렬 전환은 연속 5개 태스크가 에스컬레이션 없이 통과한 뒤에 한다.
- Windows + Git Bash 기준으로 작성됐다. `/`로 시작하는 인자는 `MSYS_NO_PATHCONV=1`이 필요하다.

## 참고

- 용어: [CONTEXT.md](CONTEXT.md)
- 정책은 코드, orca 사용법은 Orca 가이드가 정본인 이유: [ADR 0001](docs/adr/0001-policy-in-code.md)
- Orca orchestration 정본 가이드: `orca skills get orchestration`
