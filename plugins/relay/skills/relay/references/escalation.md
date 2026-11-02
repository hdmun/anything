# 에스컬레이션과 포기 (h)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (에스컬레이션)

리뷰에서 오는 에스컬레이션(`SPEC_VIOLATION`, 반복 지적, 리뷰 라운드 한도, 총 라운드 한도)은 (g)의 `review-branch`가 판정한다. 그 밖의 트리거:

| 트리거 | 행동 |
|---|---|
| 워커가 `escalation` 발신 | Opus |
| 같은 Task의 기동 실패 2회 | **사람**, 재시도 금지 |
| 무응답 판정 (e) | **사람** |

### 시도와 라운드를 구분한다

용어는 `CONTEXT.md`가 정본이다. 셋을 섞으면 예산이 엉뚱하게 깎인다.

| 용어 | 뜻 | 세는 법 (세션 폐기 후에도 남는 곳) |
|---|---|---|
| **기동 실패** | 워커가 태스크 프롬프트를 받기 전에 실패한 것. Orca가 보고한 실패(`agent_readiness`, `agent_prompt_blocked` 등)와 (d)의 **전달 확인** 실패를 모두 포함한다. **라운드가 아니다** | Orca Task의 실패 이력 |
| **구현 라운드** | 게이트를 통과해 커밋으로 남은 구현 한 번 | `git log <base>..HEAD`의 `Implemented-by:` 트레일러 커밋 수 — **트레일러가 빠진 커밋은 세지 못한다** |
| **리뷰 라운드** | 리뷰 리포트 하나 | `.ai/reviews/T-NNN.r*.json` 파일 개수 |
| **총 라운드** | 구현 라운드 + 리뷰 라운드 | 위 둘의 합 (`review-branch`가 센다) |

- **기동 실패는 2회에서 멈춘다.** Orca는 같은 Task가 3회 연속 실패하면 circuit-break한다. 2회째에 재시도하면 마지막 기회를 원인 모른 채 쓰게 된다(T-004에서 구현·리뷰 Task 둘 다 그 직전까지 갔다).
  원인을 찾아 해소했다면 기존 Task를 포기하고 **새 Task**로 다시 시작한다 — 재시도가 아니라 재출발이다. 재출발 전에 Task 밖에서 `terminal create` → `tui-idle`로 준비 감지가 통과하는지 먼저 확인한다.
- **`agent_readiness` 실패는 한 번으로 그 Task를 `failed`로 만든다**(실측). 같은 Task에 `worker-start`를 다시 걸면 `task_not_startable`로 거부되므로 예산 2회를 다 쓰기 전에도 재출발은 **항상 새 Task**다. 이미 `tui-idle`이 통과하는 터미널이 있으면 **그 터미널을 `worker-start --terminal`로 그대로 재사용해도 된다**(실측: 새 Task + 같은 터미널로 기동 성공, 60초 안에 `HandleUserInput` 확인).
- 기동 실패는 환경 문제이고 구현자의 실력과 무관하므로 라운드 예산을 깎지 않는다.

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
