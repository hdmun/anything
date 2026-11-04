# 구현 워커(agy) 기동 (d)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (구현 워커 기동)

## (d) 워커 부트스트랩

**구현·리뷰 워커 모두 `worker-start`로 띄운다.** 감독 워커라야 Orca가 그 워커의 보고로 진행자를 깨운다 — (e)와 (i)가 그것을 전제한다.

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

   **`worker-start` 영수증은 Orca 가이드대로 읽는다**(`state`·`failedStage`·`next`, 실패면 `recovery-and-cleanup` reference). relay가 더하는 것은 SKILL.md 불변식의 감독 정책뿐이다.

   - 정상이면 `dispatchId`와 `launch.effective.model`(커밋 트레일러에 쓴다)을 적어 두고 턴을 끝낸다 — (e).
   - 기동 실패는 Orca 가이드의 복구 절차대로 다시 띄운다. Orca의 3회 circuit-break가 끝이고, 걸리면 사람이 필요한 것으로 (h). 기동 실패는 라운드로 세지 않는다 — (h) 「시도와 라운드」.
   - `agent_prompt_blocked`·`outcome_unknown`은 불변식대로 사람을 부른다. codex 업데이트 프롬프트였다면 예방책(`~/.codex/config.toml`의 `check_for_update_on_startup = false`, `reviewer.md`)을 질문에 함께 적는다.
   - 전달 확인은 Orca가 한다(`turnStart`). relay는 따로 확인하지 않는다.

**Git Bash 주의** — `terminal send --text "/clear"` 처럼 `/`로 시작하는 인자는 Git Bash가 `C:/Program Files/Git/clear`로 경로 변환한다. `MSYS_NO_PATHCONV=1`을 앞에 붙인다.
