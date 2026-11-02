# 준비 대기 timeout 사다리와 blocked_prompt (예외 경로)

`tui-idle`이 timeout일 때만 읽는다. 구현 워커(agy)와 리뷰 워커(codex)가 함께 쓴다.

   - **`tui-idle`이 timeout이면 `worker-start`를 걸지 않는다.** Task 밖의 실패라 기동 실패 예산을 쓰지 않는다. 화면과 로그를 파일로 받아 `readiness`에 묻는다 — 셸 명령이라 비용이 0이다.

     ```bash
     # terminal read --screen 의 JSON → screen.json
     python "$RELAY/scripts/relay_cli.py" readiness --agent antigravity --screen screen.json \
       --agy-log "$(ls -t ~/.gemini/antigravity-cli/log/cli-*.log | head -1)" --retries <이미 다시 건 횟수> [--recreated]        --command '<terminal create 에 실제로 준 --command 값>'
     ```

     | `action` | 할 일 |
     |---|---|
     | `retry_tui_idle` | `wait_seconds`(30초) 뒤 `tui-idle`을 다시 건다. 다시 timeout이면 `--retries`를 1 올려 또 묻는다 |
     | `recreate_terminal` | 터미널을 닫고 새로 만든 뒤 `--recreated`를 붙여 같은 사다리를 다시 탄다. `reason: bare_launch_command`면 단독 `agy`로 띄운 것이다 — 기다려도 풀리지 않으므로 재시도 없이 바로 나온다. `reason: header_scrolled_out`도 그렇다 — 화면은 `>`·Idle로 정상인데 긴 세션으로 `Antigravity CLI` 머리글이 Orca가 보관하는 꼬리(최대 2000줄) 밖으로 밀려났다. 새 터미널은 결정의 `launch_command` 값을 `--command`로 쓴다 |
     | `human` | `reason`과 함께 사람 호출: `blocked_prompt`(trust·update·permission·codex 승인창 — 자동 응답 금지), `not_signed_in`(로그에 로그인 기록 없음), `no_prompt`(입력창이 아직 없다), `recreate_failed`(재생성도 실패), `bare_launch_command`(재생성한 뒤에도 단독 `agy`로 띄웠다), `header_scrolled_out`(새 터미널에서도 머리글이 없다) |

     사다리(로그인 확인 → 재시도 3회 → 1회 재생성 → 사람)의 정본은 `scripts/relaylib/orca.py`다.
     - **이 사다리는 예비 수단이다.** 준비 감지 실패의 대부분은 단독 `agy` 실행 경로 탓이었다(`--command` 설명 참고). 시작 명령을 지키면 사다리까지 올 일이 드물다. 그래도 timeout이 나면 사다리대로 한다.



## 리뷰 워커(codex)의 경우



  - **`tui-idle`이 timeout이면 `worker-start`를 걸지 않는다.** 화면을 받아 `readiness`에 묻는다. 확인창이면 `human / blocked_prompt`가 나온다 — **키 입력으로 응답하지 말고 사람을 부른다.** 특히 `Hooks need review`는 hook 신뢰가 코드 실행 권한이라 사용자만 결정한다.

    ```bash
    # terminal read --screen 의 JSON → screen.json
    python "$RELAY/scripts/relay_cli.py" readiness --agent codex --screen screen.json --retries <이미 다시 건 횟수> [--recreated]
    ```

    `action` 표는 구현자 4번과 같다(`--agy-log`는 codex에 쓰지 않는다).

    **`human / blocked_prompt` 뒤에는 사람이 처리하고 나서 같은 자리에서 이어간다.** `worker-start`를 아직 걸지 않았으니 Task는 멀쩡하다.
    1. 사람이 그 터미널에서 직접 응답한다(hook 신뢰는 `config.toml`에 저장되어 플러그인이 다시 갱신되기 전까진 다시 뜨지 않는다).
    2. 사람이 끝났다고 알리면 **같은 터미널**에 `tui-idle`을 다시 건다. 새 터미널이나 새 Task를 만들지 않는다.
    3. 통과하면 **같은 Task**로 `worker-start --terminal <h>`를 건다. 다시 timeout이면 `readiness`부터 다시 — 확인창이 연달아 뜰 수 있다.
