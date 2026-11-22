# Codex statusline

Codex CLI의 custom MCP statusline이다. 모델 · 작업 폴더의 전체 경로 · 컨텍스트 사용률을 표시한다. 값이 없으면 `Codex` 또는 `—`로 표시한다. 외부 의존성 없이 Python 3로 실행한다.

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
3. `/statusline` → **Choose a status line provider** → **모델 · 작업 폴더 · 컨텍스트**를 선택한다.
4. 다른 스레드로 전환해 모델·경로·사용률이 해당 스레드를 따르는지 확인한다.

실패로 기본 footer가 나오면 F2에서 오류를 확인한다. 오류나 timeout은 polling을 멈추므로 `/statusline`에서 다시 선택한다. 파일을 갱신한 뒤에는 stdio 프로세스를 재시작한다.

## 검증

```powershell
python codex-statusline/self_check.py
python codex-statusline/self_check.py "$env:USERPROFILE/.codex/statusline/statusline.py"
codex mcp get codex-statusline
```

검증은 실제 stdio 프로세스에서 초기화·도구 광고·대표 스냅샷·optional 누락·연속 스레드 변경·잘못된 URI를 확인한다. 실제 TUI 표시는 위 선택 절차를 거쳐 별도로 확인한다.
