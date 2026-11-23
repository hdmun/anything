# Codex statusline

Codex CLI의 custom MCP statusline이다. `claude-statusline` 구현과 `agy-statusline/PROMPT.md`의 표시 방식을 참고했다. 외부 의존성 없이 Python 3로 실행한다. 없는 값은 생략한다.

```text
🤖 GPT-6 (high) | 📁 anything | 🧠 ██████░░░░ 62% | 124k/200k | ⏳ codex 5h0m 30% (🔄 2h9m) | 💰 $1.23
```

| 기존 항목 | Codex 대응 |
| --- | --- |
| 모델·effort·폴더명 | `thread.model.display_name`, `reasoning_level`, `workspace.cwd` |
| 컨텍스트 게이지·토큰 | `thread.usage.context`의 `used_percentage`, `used_tokens`, `context_window_size` |
| 한도 쓴 %·리셋 | `account.rate_limits`의 primary/secondary window, 실제 이름·기간 표시 |
| 비용 | `thread.usage.cost.total_cost_usd` |
| Git 브랜치·변경 표시, 실행 시간, recap | 스냅샷에 없음: 생략 |

게이지는 10칸이며 사용률 50% 미만은 초록, 80% 미만은 노랑, 그 이상은 빨강이다. 한도도 쓴 %(`used_percent`)를 보이고 같은 기준으로 색을 고른다. ANSI 대신 UI tree 색상을 사용한다. 타입 정의에 수직 레이아웃이 없어, 고정 2~3줄 대신 `row`의 자동 줄바꿈으로 표시한다. 별도 git 명령이나 transcript 탐색은 하지 않는다.

공식 `create-statusline` 스킬의 `assets/statusline.py` starter를 재사용했다. 매 `resources/read` 요청의 스냅샷을 사용하므로 스레드별 상태를 저장하지 않는다.

## 설치

```powershell
pwsh -NoProfile -File codex-statusline/install.ps1 -Check   # 먼저 보기 (아무것도 쓰지 않는다)
pwsh -NoProfile -File codex-statusline/install.ps1
```

대상은 `~/.codex` 와 `~/.agent-accounts/codex/*` 다(각자 `CODEX_HOME`). 폴더가 없으면 건너뛴다. 폴더마다 아래를 맞춘다.

- `statusline.py` 를 `<CODEX_HOME>/statusline/statusline.py` 로 복사한다. 워크트리를 지워도 복사본은 남는다.
- `config.toml` 에 키 세 개를 둔다. 같은 키에 다른 값이 있으면 덮어쓴다. 다른 키·주석·줄바꿈은 그대로 둔다.

```toml
[features]
tui_extensions_statusline = true

[mcp_servers.codex-statusline]
command = "<python 실행 파일>"
args = ["-u", "<CODEX_HOME>/statusline/statusline.py"]

[tui]
status_line_provider = { server = "codex-statusline", tool = "statusline" }
```

- `<python 실행 파일>` 은 `python` 의 `sys.executable` 이다. Python 을 실행하지 못하면 `실패: …` 를 출력하고 아무것도 쓰지 않는다. `-Python <명령>` 으로 다른 명령을 줄 수 있다.
- 처음 설치한 뒤에는 TUI 를 재시작하고 새 대화에서 상태 줄이 나오는지 한 번 확인한다. 다른 스레드로 전환해 모델·경로·사용률이 해당 스레드를 따르는지도 본다.

`install.ps1` 은 pc-setup 의 **저장소 도구**다([../pc-setup/repo-tools.md](../pc-setup/repo-tools.md)). 셋업이 `-Check` 와 맞춤 실행을 대신 부른다.

출력은 한 줄이다: `그대로` / `다름 (<파일>, …)`(`-Check`) / `바꿈 (<파일>, …)` / `실패: …`. 여러 파일이면 `실패` 가 먼저 보인다.

실패로 기본 footer가 나오면 F2에서 오류를 확인한다. 오류나 timeout은 polling을 멈추므로 `/statusline` → **Choose a status line provider** 에서 다시 선택한다. 파일을 갱신한 뒤에는 stdio 프로세스를 재시작한다.

## 검증

```powershell
python codex-statusline/self_check.py
python codex-statusline/self_check.py "$env:USERPROFILE/.codex/statusline/statusline.py"
codex mcp get codex-statusline
```

검증은 실제 stdio 프로세스에서 초기화·도구 광고·대표 스냅샷·optional 누락·연속 스레드 변경·잘못된 URI를 확인한다. 실제 TUI 표시는 위 선택 절차를 거쳐 별도로 확인한다.
