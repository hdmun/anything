# 구현 워커(agy) 기동 (d)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (구현 워커 기동)

## (d) 워커 부트스트랩

**구현·리뷰 워커 모두 `worker-start`로 띄운다.** 감독 워커라야 Orca가 그 워커의 보고로 진행자를 깨운다 — (e)가 그것을 전제한다.

**구현 워커(agy)**

워크트리는 이슈 워크트리 하나다 — handoff 가 만들었고, 기준선 게이트는 시작 때 돌렸다((c) 4). 워커는 그 안에서 `--worktree current` 로 뜬다(ADR 0010). `<base>` 는 이 태스크의 스냅숏 커밋 직후 HEAD다((c) 태스크마다 1).

1. **agy trust는 Orca가 등록한다.** `worker-start --agent antigravity`는 agy를 띄우기 직전에 그 워크트리를 `~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces`에 직접 추가한다(2026-11-02 실측). 그래서 `trust add`는 하지 않는다.
   - Orca는 추가만 하고 지우지 않는다. PR 을 열 때 relay가 한 번 지운다 — (i). 지우지 않으면 목록이 계속 늘어난다.

2. **예열 — 워커를 띄우기 전에 agy 업데이트를 Task 밖에서 끝낸다.** 구현 기동과 수정 라운드 모두 그렇다.

   ```bash
   python "$RELAY/scripts/relay_cli.py" warmup agy
   # {"action": "ready", "version": "1.2.16", "updated": true, "unverified": true}
   ```

   - agy는 실행할 때마다 백그라운드로 자동 업데이트하고 다음 실행부터 새 버전을 쓴다. 막지 않는 대신 여기서 `agy update`로 먼저 끝내, **Task 도중에 버전이 바뀌지 않게** 한다(CONTEXT.md 「예열」).
   - `unverified: true`면 그 버전은 smoke를 통과한 적이 없다. 사람이 필요한 것으로 알리고 `relay_cli.py smoke --agent antigravity`를 먼저 돌린다. 실패하면 워커를 띄우지 않는다 — (h).
   - `human`이면 업데이트 실패 — (h).

3. **`worker-start --agent antigravity`로 띄운다.** 먼저 기동 인자를 결정기에 묻는다:

   ```bash
   python "$RELAY/scripts/relay_cli.py" model implementer
   # {"action": "launch", "agent": "antigravity", "model": null, "effort": null, "source": "agy_default"}
   ```

   - `human / agy_model_invalid`면 설정이 agy와 맞지 않는다(`detail`에 사유). `human / effort_needs_model`이면 설정에 effort만 있다 — Orca는 `--effort`를 `--model` 없이 받지 않는다. 어느 쪽이든 기동하지 않고 `detail`을 (h)로 올린다.
   - `launch`면 Orca 가이드의 `worker-start` 에 relay가 정하는 값만 채운다:
     - `--spec` — `I-<n> 구현. 역할: .ai/roles/implementer.md / spec: .ai/specs/I-<n>-<슬러그>.md / base: <base>`
     - `--worktree current` — 이슈 워크트리
     - `--parent <태스크의 task_id>` — (c) 5 에서 만든 태스크
     - `--agent antigravity`, 그리고 `model`이 있을 때만 `--model <model>`(`effort`가 있으면 `--effort <effort>`)
   - `model`이 `null`이면 **agy 기본 모델**로 뜬다. 응답의 `launch.effective.model`도 `null`이다.

   **`worker-start` 영수증은 Orca 가이드대로 읽는다**(`state`·`failedStage`·`next`, 실패면 `recovery-and-cleanup` reference). relay가 더하는 것은 SKILL.md 불변식의 감독 정책뿐이다.

   - 정상이면 `dispatchId`와 `launch.effective.model`(커밋 트레일러에 쓴다)을 적어 두고 턴을 끝낸다 — (e).
   - 기동 실패는 Orca 가이드의 복구 절차대로 다시 띄운다. Orca의 3회 circuit-break가 끝이고, 걸리면 사람이 필요한 것으로 (h). 기동 실패는 라운드로 세지 않는다 — (h) 「시도와 라운드」.
   - `agent_prompt_blocked`·`outcome_unknown`은 불변식대로 사람을 부른다. codex 업데이트 프롬프트였다면 예방책(`~/.codex/config.toml`의 `check_for_update_on_startup = false`, `reviewer.md`)을 질문에 함께 적는다.
   - 전달 확인은 Orca가 한다(`turnStart`). relay는 따로 확인하지 않는다.

**Git Bash 주의** — `terminal send --text "/clear"` 처럼 `/`로 시작하는 인자는 Git Bash가 `C:/Program Files/Git/clear`로 경로 변환한다. `MSYS_NO_PATHCONV=1`을 앞에 붙인다.
