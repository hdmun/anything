# Orca 1.4.247 픽스처 후보

2026-11-04 버리는 Run `run_0444a45255d0` 에서 실측했다. 아직 어떤 테스트도 이 파일들을 읽지 않는다.
상위 폴더의 픽스처는 2.0.0 이전 모양이다. 테스트에 쓸지는 relay 재구성 구현 때 정한다.

## agy (`--agent antigravity`, 60초 sleep Task)

| 파일 | 시점 |
|---|---|
| `agy-worker-start.json` | 기동 영수증 (간결 보기) |
| `agy-worker-list-working.json`, `agy-worker-show-working.json` | 작업 중 (기동 후 약 10초) |
| `agy-worker-show-working-mid.json` | 작업 중 (기동 후 약 30초) |
| `agy-worker-show-done.json`, `agy-worker-list-done.json` | `worker_done` 직후 |
| `agy-check-worker-done.json` | `check` 로 받은 `worker_done` 메일 |

관찰: 모든 시점에 `projection.liveness = live / agent_status`, `evidence.liveStatus = fresh` 였다.
`worker_done` 뒤에도 `stage.activity` 는 `working` 으로 남았다. 완료는 `outcome: succeeded` 로 본다.

## codex (`--agent codex`, `git status --short` Task)

| 파일 | 시점 |
|---|---|
| `codex-worker-start-yolo.json` | 기동 영수증 (`--full`) |
| `codex-worker-show-working-yolo.json`, `codex-worker-list-working-yolo.json` | 작업 중 |
| `codex-terminal-show-yolo.json` | 작업 중 `terminal show` |
| `codex-check-worker-done.json` | `worker_done` 메일 |

관찰: 사용자가 Orca 의 codex 권한 모드를 승인 모드로 바꿨다. 그런데도 `worker-start` 가 띄운 codex 는
`--dangerously-bypass-approvals-and-sandbox` 로 실행되어 승인창이 뜨지 않았다.
그래서 이 파일들은 승인창 상태가 아니라 yolo 상태(`agentWait: null`)다.
