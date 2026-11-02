# 리뷰 워커(codex) 기동 (d)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (리뷰 워커 기동)

**리뷰 워커(codex)**

사전 조건과 모델을 `model reviewer`에 묻는다:

```bash
python "$RELAY/scripts/relay_cli.py" model reviewer
# {"action": "launch", "agent": "codex", "model": "gpt-6-luna", "effort": "high"}
```

- `launch`면 그 `model`·`effort`로 띄운다. 둘 다 모델 설정 파일의 값이고, effort는 설정 파일에 없으면 `high`다.
- `human`(`reviewer_model_unset`)이면 기동하지 말고 사용자에게 `~/.relay/models.json`(또는 `.ai/relay-models.json`)에 `{"reviewer": {"model": "<모델>"}}`을 추가해 달라고 한다.
- `human`(`codex_prereq_missing`)이면 기동하지 말고 `missing`에 적힌 키를 사용자에게 추가해 달라고 한다:

  ```toml
  check_for_update_on_startup = false          # 최상위. 업데이트 프롬프트가 기동을 막는다 (agent_prompt_blocked)

  [tui]
  terminal_title = ["app-name", "activity", "project-name"]   # 제목에 "codex"가 있어야 Orca가 준비를 감지한다
  ```

  두 번째 키가 필요한 이유: Orca(1.4.216)는 codex가 준비됐는지를 **배너의 `model:`/`directory:` 라벨**이나 **터미널 제목 속 `codex`** 로만 판정한다.
  codex 0.159는 배너에서 라벨을 빼고 제목을 폴더 이름으로 바꿔 둘 다 사라졌고, 그 결과 `agent_readiness timeout`이 난다. 이 키를 넣으면 6초 안에 준비가 감지된다.

**기동 전에 리뷰할 diff가 실제로 있는지 확인한다.** 빈 범위를 넘기면 리뷰어는 아무것도 검증하지 않고 `pass`를 낸다 — 정상 통과와 구분되지 않는 가장 비싼 실패다.

```bash
python "$RELAY/scripts/relay_cli.py" diff-guard --worktree <worktree> --base <base> ; echo "exit=$?"
```

- 종료코드 1이면 **리뷰 워커를 띄우지 않는다.** `<base>`가 틀렸거나 (f)의 구현 커밋이 빠진 것이다. 둘 중 무엇인지 확인하고 고친 뒤 다시 본다.
  알아낼 수 없으면 사람을 부른다. 이 확인은 셸 명령이라 비용이 0이다.
- 리뷰어 역할 파일에도 같은 확인이 있다(빈 diff면 `--outcome failed`). 진행자 쪽 확인이 1차, 역할 파일 쪽은 템플릿이 갱신된 저장소에서만 동작하는 2차 방어다.

- **`worker-start --agent codex`로 띄운다.** preamble SUB-DISPATCH의 `worker-start` 명령을 그대로 쓰고, relay가 정하는 값만 채운다:
  - `--spec` — `T-NNN 리뷰 rN. 역할: .ai/roles/reviewer.md / spec: .ai/specs/T-NNN-<슬러그>.md / base: <base> / 리포트: .ai/reviews/T-NNN.rN.json`
  - `--worktree id:<wt>` — 구현 워커와 같은 워크트리
  - `--agent codex --model <model reviewer 의 model> --effort <model reviewer 의 effort>`

  - Orca는 codex를 띄울 때 승인·샌드박스를 끄는 인자를 스스로 붙인다. 그래서 워커의 `worker_done` 전송이 샌드박스에 막히지 않는다(2026-11-02 실측 4/4). 직접 명령줄을 만들지 않는다.
  - 응답은 구현 워커와 같이 `startup`에 해석시킨다 — `implementer.md` 4의 표. `ok`의 `model`(= `launch.effective.model`)이 리뷰 리포트 커밋 트레일러의 모델이다.
- **구현 워커와 같은 worktree를 쓴다.** 파이프라인이 순차라 충돌이 없다. (f)에서 게이트 통과 즉시 구현 커밋을 만들어두므로, 리뷰어는 `codex review <base>..HEAD`처럼 커밋된 범위를 본다 — `--uncommitted`를 전제하지 않는다.
- **그 `<base>`를 Task spec에 반드시 적는다.** 리뷰어는 base를 추측할 수 없고, 범위를 잘못 잡으면 **조용히 빈 diff를 보고 `pass`를 낸다.** 정상 통과와 구분되지 않으므로 이 파이프라인에서 가장 비싼 실패다. 1번에서 적어둔 커밋 SHA를 그대로 넣는다.
- 저장소의 역할 파일(`.ai/roles/reviewer.md`)도 같은 전제로 맞춰져 있어야 한다. **커밋 정책을 바꿀 때 역할 파일을 함께 고치지 않으면 리뷰어가 `--uncommitted`로 빈 diff를 검증하게 된다**. `/relay:init --check`로 확인한다.
- **기록하는 `model`은 `startup`의 `model`(`launch.effective.model`)이다** — 리뷰 리포트 커밋의 트레일러에 쓴다. 요청한 값이 아니라 Orca가 실제로 띄운 값이다.
