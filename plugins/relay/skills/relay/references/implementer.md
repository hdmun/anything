# 구현 워커(agy) 기동 (d)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (구현 워커 기동)

## (d) 워커 부트스트랩

**구현·리뷰 워커 모두 `worker-start`로 띄운다.** 감독 워커라야 `worker-list`의 fleet projection, `worker-read`, `worker-release`가 열리며 — (e)와 (i)가 그것을 전제한다.

**구현 워커(agy)**

1. `worktree create` 로 worktree 경로를 확보한다. relay 값: `--name T-NNN`, `--base-branch main`, `--setup run`.
   - **`--base-branch`를 반드시 명시한다.** 생략하면 repo의 `defaultBaseRef`를 쓰는데, 그 값이 `null`인 저장소에서는 엉뚱한 지점에서 분기된다.
   - 만든 직후 `git -C <worktree> log --oneline -1`로 base가 의도한 커밋인지 확인한다. 어긋났으면 `git -C <worktree> reset --hard <base>`로 맞춘다(추적되지 않은 파일은 보존된다).
   - **이 커밋 SHA를 적어둔다.** 리뷰 워커의 Task spec에 `<base>`로 넣어야 한다.

   **그리고 워커를 띄우기 전에 게이트를 한 번 돌려 기준선이 녹색인지 확인한다.** 이것이 (d) 전체에서 가장 자주 걸리는 함정이다.

   - **fresh worktree에는 의존성이 설치되어 있지 않다.**
   - `--setup run`은 저장소에 setup 훅이 있을 때만 이 일을 대신한다. 훅이 없거나 `--setup skip`을 썼다면 직접 준비한다.
   - **기준선이 빨간 상태로 워커를 띄우면 안 된다.** 구현자가 자기 잘못과 환경 문제를 구분할 수 없고, 게이트 자체 루프 3회를 환경 문제로 소진한 뒤 `escalation`을 올린다. 라운드 하나가 통째로 낭비된다.
   - 종료코드로 판정한다. 파이프로 넘기면 실패가 사라진다 — (f) 참조.

2. **agy trust는 Orca가 등록한다.** `worker-start --agent antigravity`는 agy를 띄우기 직전에 그 워크트리를 `~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces`에 직접 추가한다(2026-11-02 실측). 그래서 `trust add`는 하지 않는다.
   - Orca는 추가만 하고 지우지 않는다. 성공 종료 때 relay가 지운다 — (i)의 「하위 워커 정리」. 지우지 않으면 목록이 계속 늘어난다.

3. **예열 — 워커를 띄우기 전에 agy 업데이트를 Task 밖에서 끝낸다.** 구현 기동과 수정 라운드 재기동 모두 그렇다.

   ```bash
   python "$RELAY/scripts/relay_cli.py" warmup agy
   # {"action": "ready", "version": "1.2.16", "updated": true, "unverified": true}
   ```

   - agy는 실행할 때마다 백그라운드로 자동 업데이트하고 다음 실행부터 새 버전을 쓴다. 막지 않는 대신 여기서 `agy update`로 먼저 끝내, **Task 도중에 버전이 바뀌지 않게** 한다(CONTEXT.md 「예열」).
   - `unverified: true`면 그 버전은 smoke를 통과한 적이 없다. 사람이 필요한 것으로 알리고 `relay_cli.py smoke --agent antigravity`를 먼저 돌린다. 실패하면 워커를 띄우지 않는다 — (h).
   - `human`이면 업데이트 실패 — (h).

4. **`worker-start --agent antigravity`로 띄운다.** 먼저 기동 인자를 결정기에 묻는다:

   ```bash
   python "$RELAY/scripts/relay_cli.py" model implementer
   # {"action": "launch", "agent": "antigravity", "model": null, "effort": null, "source": "agy_default"}
   ```

   - `human / agy_model_invalid`면 설정이 agy와 맞지 않는다(`detail`에 사유). `human / effort_needs_model`이면 설정에 effort만 있다 — Orca는 `--effort`를 `--model` 없이 받지 않는다. 어느 쪽이든 기동하지 않고 `detail`을 (h)로 올린다.
   - `launch`면 preamble SUB-DISPATCH의 `worker-start` 명령을 그대로 쓰고, relay가 정하는 값만 채운다:
     - `--spec` — `T-NNN 구현. 역할: .ai/roles/implementer.md / spec: .ai/specs/T-NNN-<슬러그>.md / base: <base>`
     - `--worktree id:<wt>` — 1에서 만든 워크트리
     - `--agent antigravity`, 그리고 `model`이 있을 때만 `--model <model>`(`effort`가 있으면 `--effort <effort>`)
   - `model`이 `null`이면 **agy 기본 모델**로 뜬다. 응답의 `launch.effective.model`도 `null`이다.

   **`worker-start` 응답은 `startup`에 해석시킨다.** 종료코드 0과 `ok`만으로 믿지 않는다 — 준비 감지에 실패해도 `ok: true`가 올 수 있다(예: `failedStage: agent_readiness`).

   ```bash
   # worker-start 의 JSON 응답을 start.json 으로 받는다
   python "$RELAY/scripts/relay_cli.py" startup --response start.json [--prior-failures <이 태스크 계열의 이전 기동 실패 수>]
   ```

   | `action` | 할 일 |
   |---|---|
   | `ok` | `dispatch`와 `model`(= `launch.effective.model`, 커밋 트레일러에 쓴다)을 기록하고 (e)의 대기로. Orca가 `turnStart: observed`로 전달을 확인했다 |
   | `lookup_dispatch` | `dispatch-show --task <task_id>` 로 조회한다. 추측하지 말 것 |
   | `confirm_delivery` | (`turn_start_unobserved`) 입력은 썼는데 에이전트가 턴을 시작했는지 Orca가 못 봤다. 실패로 단정하지 않고 60초 뒤 `dispatch-show`의 `status`로 확인한다. `pending`이면 전달 실패 = 기동 실패다 — 재전송하지 않고 `worker-retain` 후 사람이 필요한 것으로 (h). **기동 실패 예산이 남아 있어도 스스로 재출발하지 않는다** — 입력이 늦게 도착하면 같은 Task를 두 워커가 하게 된다. 재출발은 답이 온 뒤 아래 `retry` 행대로. `dispatched`/`completed`면 정상 |
   | `retry` | 기동 실패 1회. **그 Task는 이미 `failed`다.** 다시 띄우기 전에 Orca 가이드 `recovery-and-cleanup` reference를 읽고 그 replacement 절차(`--task <실패한 task_id> --retry-of <dispatch_id>`, 배치·`--agent` 인자를 다시 준다)를 따른다. 실패한 시도가 남긴 터미널은 영수증의 `worker-release`로 정리한다 |
   | `human` | `startup_budget`(기동 실패 2회), `agent_prompt_blocked` 등 — 사람이 필요한 것으로 (h). `agent_prompt_blocked`면 그 프롬프트는 사람이 워커 터미널에서 직접 처리한다 — 진행자는 키를 보내지 않고, 보낼 키를 선택지로 제안하지도 않는다. codex 업데이트 프롬프트면 예방책(`~/.codex/config.toml`의 `check_for_update_on_startup = false`, `reviewer.md`)을 질문에 함께 적는다 |

   - 기동 실패는 라운드로 세지 않는다 — (h) 「시도와 라운드」.
   - 전달 확인은 Orca의 `turnStart`로 한다. agy 로그를 직접 세던 절차(`HandleUserInput`)는 Orca 1.4.245가 antigravity의 턴 시작을 관측하면서 지웠다(plan 트랙 0).

**Git Bash 주의** — `terminal send --text "/clear"` 처럼 `/`로 시작하는 인자는 Git Bash가 `C:/Program Files/Git/clear`로 경로 변환한다. `MSYS_NO_PATHCONV=1`을 앞에 붙인다.
