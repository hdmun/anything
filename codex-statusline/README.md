# Codex statusline

Codex CLI의 custom MCP statusline이다. `claude-statusline` 구현과 `agy-statusline/PROMPT.md`의 표시 방식을 참고했다. 외부 의존성 없이 Python 3로 실행한다. 없는 값은 생략한다.

```text
🤖 GPT-6 (high) | 📁 anything | 🧠 ██████░░░░ 62% | 124k/200k | ⏳ codex 5h0m 70% left (🔄 2h9m) | 💰 $1.23
```

| 기존 항목 | Codex 대응 |
| --- | --- |
| 모델·effort·폴더명 | `thread.model.display_name`, `reasoning_level`, `workspace.cwd` |
| 컨텍스트 게이지·토큰 | `thread.usage.context`의 `used_percentage`, `used_tokens`, `context_window_size` |
| 남은 한도·리셋 | `account.rate_limits`의 primary/secondary window, 실제 이름·기간 표시 |
| 비용 | `thread.usage.cost.total_cost_usd` |
| Git 브랜치·변경 표시, 실행 시간, recap | 스냅샷에 없음: 생략 |

게이지는 10칸이며 사용률 50% 미만은 초록, 80% 미만은 노랑, 그 이상은 빨강이다. 한도도 같은 기준이다. ANSI 대신 UI tree 색상을 사용한다. 타입 정의에 수직 레이아웃이 없어, 고정 2~3줄 대신 `row`의 자동 줄바꿈으로 표시한다. 별도 git 명령이나 transcript 탐색은 하지 않는다.

공식 `create-statusline` 스킬의 `assets/statusline.py` starter를 재사용했다. 매 `resources/read` 요청의 스냅샷을 사용하므로 스레드별 상태를 저장하지 않는다.

## 설치

저장소 루트에서 PowerShell로 실행한다. 워크트리를 삭제해도 설치본은 남는다.

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE/.codex/statusline" | Out-Null
Copy-Item codex-statusline/statusline.py "$env:USERPROFILE/.codex/statusline/statusline.py"
codex mcp add codex-statusline -- (Get-Command python).Source -u "$env:USERPROFILE/.codex/statusline/statusline.py"
```

1. Codex TUI의 `/experimental`에서 **Custom status line**을 활성화한다.
2. TUI를 재시작하고 새 대화를 연다.
3. `/statusline` → **Choose a status line provider** → **Codex 사용량 statusline**을 선택한다.
4. 다른 스레드로 전환해 모델·경로·사용률이 해당 스레드를 따르는지 확인한다.

실패로 기본 footer가 나오면 F2에서 오류를 확인한다. 오류나 timeout은 polling을 멈추므로 `/statusline`에서 다시 선택한다. 파일을 갱신한 뒤에는 stdio 프로세스를 재시작한다.

## 검증

```powershell
python codex-statusline/self_check.py
python codex-statusline/self_check.py "$env:USERPROFILE/.codex/statusline/statusline.py"
codex mcp get codex-statusline
```

검증은 실제 stdio 프로세스에서 초기화·도구 광고·대표 스냅샷·optional 누락·연속 스레드 변경·잘못된 URI를 확인한다. 실제 TUI 표시는 위 선택 절차를 거쳐 별도로 확인한다.
