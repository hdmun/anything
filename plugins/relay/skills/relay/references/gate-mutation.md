# 소스를 고쳐 가며 도는 게이트(변이 테스트) (예외 경로)

게이트가 변이 테스트일 때만 읽는다.

변이 테스트 도구는 소스에 변이를 심고 테스트를 돌린 뒤 되돌리기를 반복한다. 실측(poker-server T-007): `tools/mutate/mutate.py`가 변이마다 `go test ./...` 전체를 돌려 25~40분 걸렸다.

- **다른 게이트를 먼저 끝내고 변이 게이트는 마지막에 백그라운드로 돌린다**(예: Bash의 `run_in_background`). 끝나면 종료코드로 판정한다.
- **변이 게이트가 도는 동안 같은 워크트리에서 `go test` 등 다른 게이트를 돌리지 않는다.** 변이가 심어진 소스를 테스트해 거짓 FAIL이 난다(실측: `internal/analysis`).
- **그동안 `git status`에 보이는 소스 변경은 변이 잔재일 수 있다.** 변이 도구가 살아 있는지 먼저 본다:

  ```bash
  powershell -NoProfile -Command 'Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match "mutate" } | Select-Object ProcessId, CommandLine'
  ```

  - 살아 있으면 끝날 때까지 기다린다. 그 변경을 고치거나 되돌리지 않는다.
  - 프로세스가 없는데 워커가 만들지 않은 변경이 남아 있으면 도구가 복원하지 못한 것이다. 커밋하지 말고 `git diff`를 첨부해 사람을 부른다.
- **변이 게이트가 끝나고 `git status`가 깨끗해진 뒤에만 아래의 구현 커밋을 만든다.** 도는 중에 커밋하면 변이가 커밋에 섞인다.
