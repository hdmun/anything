# 구현 워커(agy) 기동 (d)

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (구현 워커 기동)

## (d) 워커 부트스트랩

**구현·리뷰 워커 모두 `worker-start`로 띄운다.** 감독 워커라야 `worker-list`의 fleet projection, `worker-read`, `worker-release`가 열리며 — (e)와 (i)가 그것을 전제한다.

**구현 워커(agy)**

1. `worktree create` 로 worktree 경로를 확보한다. relay 값: `--name T-NNN`, `--base-branch main`, `--setup run`.
   - **`--base-branch`를 반드시 명시한다.** 생략하면 repo의 `defaultBaseRef`를 쓰는데, 그 값이 `null`인 저장소에서는 엉뚱한 지점에서 분기된다.
   - 만든 직후 `git -C <worktree> log --oneline -1`로 base가 의도한 커밋인지 확인한다. 어긋났으면 `git -C <worktree> reset --hard <base>`로 맞춘다(추적되지 않은 파일은 보존된다).
   - **이 커밋 SHA를 적어둔다.** 리뷰 워커의 Task spec에 `<base>`로 넣어야 한다.

   **그리고 worker-start 전에 게이트를 한 번 돌려 기준선이 녹색인지 확인한다.** 이것이 (d) 전체에서 가장 자주 걸리는 함정이다.

   - **fresh worktree에는 의존성이 설치되어 있지 않다.**
   - `--setup run`은 저장소에 setup 훅이 있을 때만 이 일을 대신한다. 훅이 없거나 `--setup skip`을 썼다면 직접 준비한다.
   - **기준선이 빨간 상태로 워커를 띄우면 안 된다.** 구현자가 자기 잘못과 환경 문제를 구분할 수 없고, 게이트 자체 루프 3회를 환경 문제로 소진한 뒤 `escalation`을 올린다. 라운드 하나가 통째로 낭비된다.
   - 종료코드로 판정한다. 파이프로 넘기면 실패가 사라진다 — (f) 참조.

2. **`~/.gemini/antigravity-cli/settings.json`의 `trustedWorkspaces` 배열에 그 worktree 경로를 추가한다.**
   - 등록하지 않으면 agy가 "Do you trust the contents of this project?" 프롬프트에서 멈춘다. **기동 방식과 무관하게 필수다.**
   - 더 나쁜 점: 사람이 프롬프트를 해소해도 **스크롤백에 남은 텍스트 때문에 감지가 풀리지 않는다.** 사전 등록이 유일하게 깨끗한 해법이다.
   - 성공 종료 때 이 항목을 지운다 — (i)의 「워커 정리」. 지우는 단계가 없으면 단조 증가한다.

   ```bash
   python "$RELAY/scripts/relay_cli.py" trust add "<worktree path>"     # added: / already trusted:
   ```

   경로 정규화(슬래시 → 백슬래시)와 대소문자 무시 비교는 스크립트가 한다.

3. **예열 — 터미널을 만들기 전에 agy 업데이트를 Task 밖에서 끝낸다.** 구현 기동과 수정 라운드 재기동 모두 그렇다.

   ```bash
   python "$RELAY/scripts/relay_cli.py" warmup agy
   # {"action": "ready", "version": "1.2.16", "updated": true, "unverified": true}
   ```

   - agy는 실행할 때마다 백그라운드로 자동 업데이트하고 다음 실행부터 새 버전을 쓴다. 막지 않는 대신 여기서 `agy update`로 먼저 끝내, **Task 도중에 버전이 바뀌지 않게** 한다(CONTEXT.md 「예열」).
   - `unverified: true`면 그 버전은 smoke를 통과한 적이 없다. 사용자에게 알리고 `relay_cli.py smoke --agent antigravity`를 먼저 돌린다. 실패하면 워커를 띄우지 않고 사람을 부른다.
   - `human`이면 업데이트 실패 — 사람.

4. **터미널을 먼저 띄우고, 준비된 뒤에 감독을 건다.** 터미널 → `tui-idle` → `worker-start --terminal` 순서로 띄운다.

   먼저 구현자 기동 인자를 결정기에 묻는다. 설정 파일이 없으면 `launch_command`는 아래 기본값 `$null=1; agy` 그대로다:

   ```bash
   python "$RELAY/scripts/relay_cli.py" model implementer
   # {"action": "launch", "agent": "antigravity", "model": null, "effort": null, "launch_command": "$null=1; agy", "source": "agy_default"}
   ```

   `human / agy_model_invalid`면 설정이 agy와 맞지 않는 것이니(`detail`에 사유) 기동하지 말고 사용자에게 `detail`을 전한다. `launch`면 `launch_command`를 `--command`에 **그대로** 쓴다(설정이 있으면 `$null=1; agy --model … --effort …`):

   1) `terminal create` — `--worktree id:<wt>`, `--title "T-NNN agy"`, `--command '$null=1; agy'`(설정이 있으면 결정기의 `launch_command`)
   2) `terminal wait --for tui-idle --timeout-ms 30000` — Task 밖에서 통과시킨다
   3) `worker-start --task <id> --worktree id:<wt> --terminal <h>` — 재출발이면 `--retry-of <dispatch_id>`

   - **`--command`는 `'$null=1; agy'`를 그대로 쓴다.** 맨 앞 토큰이 `agy`면 Orca가 시작 명령을 에이전트로 인식해 다른 경로로 띄우는데, 그 경로에선 입력창(`>` 줄)이 Orca가 보는 출력 스트림에 남지 않아 화면은 멀쩡해도 `tui-idle`이 영영 통과하지 못한다. 앞의 문장은 아무 일도 하지 않는 PowerShell 문장으로, 일반 셸 명령으로 실행되게 할 뿐이다. 작은따옴표는 bash가 `$null`을 펼치지 않게 하려는 것이다. 이 값의 정본은 `scripts/relaylib/orca.py`의 `AGY_LAUNCH_COMMAND`다.
   - **이유**: agy는 입력창이 준비되기 전에 들어온 입력을 **조용히 버린다.** Orca는 antigravity의 전달 여부를 관측하지 못해(`provider: unsupported`) 경고도 없다.
   - `tui-idle`을 건너뛰고 바로 `worker-start --terminal`을 걸면 `agent_unconfigured`로 거부된다. Orca가 터미널에 `agentIdentity: antigravity`를 태깅하기 전이기 때문이다.
   - **`worker-start` 직전에 `tui-idle`이 `satisfied: true`여야 한다.** `worker-start`가 안에서 같은 `tui-idle` 대기를 한 번 더 하고, 거기서 실패하면 **그 Task가 곧바로 `failed`가 된다**(`task_not_startable` — 같은 Task로는 다시 `worker-start`할 수 없다). 그래서 `tui-idle`을 Task 밖에서 먼저 통과시키는 것이 유일한 안전장치다.


> `tui-idle`이 timeout이면 `references/readiness.md`를 Read 한다. 그 밖에는 읽지 않는다.


   - `--terminal`은 `--model`/`--effort`와 함께 쓸 수 없으므로 **모델·effort는 `worker-start`가 아니라 agy 명령줄**(`launch_command`의 `--model`·`--effort`)로 준다. 설정 파일이 없으면 **agy 기본 모델**로 뜬다.
     (`worker-start --agent antigravity --model`은 이제 Orca가 지원하지만, 위의 유실 문제 때문에 그 경로를 쓰지 않는다.)
   - `readiness`는 설정 파일을 직접 읽어 `recreate_terminal`의 `launch_command`에 같은 model·effort를 싣는다. 진행자 워커가 인자를 다시 조립하지 않는다.
   - **`worker-start` 응답은 `startup`에 해석시킨다.** `ok`는 믿지 않는다 — 준비 감지에 실패해도 `ok: true`가 온다(예: `failedStage: agent_readiness`, `dispatch: null`).

     ```bash
     # worker-start 의 JSON 응답을 start.json 으로 받는다
     python "$RELAY/scripts/relay_cli.py" startup --response start.json [--prior-failures <이 태스크 계열의 이전 기동 실패 수>]
     ```

     | `action` | 할 일 |
     |---|---|
     | `ok` | `dispatch`를 기록하고 5번(전달 확인)으로 |
     | `lookup_dispatch` | `dispatch-show --task <task_id>` 로 조회한다. 추측하지 말 것 |
     | `confirm_delivery` | (`turn_start_unobserved`) 입력은 썼는데 에이전트가 턴을 시작했는지 Orca가 못 봤다. 실패로 단정하지 않고 **전달부터 확인한다** — agy는 5번 로그 확인, codex는 60초 뒤 `dispatch-show`의 `status`. `pending`이면 전달 실패 = 기동 실패다(입력창이 비어 있는 경우다) — 재전송하지 말고 `worker-retain` 후 (h). `dispatched`/`completed`면 정상 |
     | `wait_tui_idle` | (`agent_unconfigured`) 터미널이 아직 에이전트로 태깅되지 않았다. Task는 멀쩡하다 — `tui-idle`부터 다시 |
     | `new_task` | 기동 실패 1회. **그 Task는 이미 `failed`다.** Task 밖에서 `tui-idle`을 통과시킨 뒤 **새 Task**로 재출발한다(통과하는 터미널이 있으면 그대로 `--terminal`로 재사용해도 된다) |
     | `human` | `startup_budget`(기동 실패 2회), `agent_prompt_blocked`(자동 응답 금지) 등 — (h) |

5. **60초 안에 전달을 확인한다.** Orca의 "입력 수락"은 전달의 증거가 아니다.

   ```bash
   # 가장 최근 agy 로그에 HandleUserInput 줄이 생겼는지 본다
   ls -t ~/.gemini/antigravity-cli/log/cli-*.log | head -1 | xargs grep -c "HandleUserInput called with text:"
   ```

   - 1 이상이면 전달됨 — (e)의 대기로 넘어간다.
   - 0이면 **전달 실패 = 기동 실패**다. 재시도하지 않고 `worker-retain` 후 사람을 부른다 — (h).
     이 단계가 없으면 빈 대기 3회(30분)를 다 쓰고 나서야 유실을 알게 된다.

**Git Bash 주의** — `terminal send --text "/clear"` 처럼 `/`로 시작하는 인자는 Git Bash가 `C:/Program Files/Git/clear`로 경로 변환한다. `MSYS_NO_PATHCONV=1`을 앞에 붙인다.
