# claude-statusline

Claude Code 상태 줄 스크립트다. Windows PowerShell 7 전용.

```
🤖 Opus 5.5 (medium) | 📁 anything | 🌿 main*
🧠 ██████░░░░ 62% | 124k/200k | ⏳ 5h 41% (🔄 2h10m)  7d 59% (🔄 2d23h) | 💰 $1.23 | ⏱ 1h23m
📝 recap: 최근 recap 문구 (터미널 폭에 맞춰 자름)
```

- 1줄: 모델(effort) · 디렉터리 · git 브랜치(`*` = 변경 있음)
- 2줄: 컨텍스트 게이지 · 토큰 · 사용 한도의 쓴 %와 리셋까지 남은 시간 · 세션 과금액 · 실행 시간
- 3줄: 대화 기록(`transcript_path`)의 가장 최근 `away_summary`. 없으면 줄이 안 나온다.
- 사용 한도는 세션 첫 응답 전에는 입력에 없다. 그때는 마지막 값을 캐시에서 읽어 보인다(리셋 시각이 지난 창은 0%, 리셋 시간 없음). 캐시: `$env:CLAUDE_CONFIG_DIR`(없으면 `~/.claude`)의 `statusline-rate-limits.json`.
- 값이 없는 항목은 빠진다. 컨텍스트·사용량 색(쓴 % 기준): 50% 미만 초록, 80% 미만 노랑, 그 이상 빨강.

## 설치

```powershell
pwsh -NoProfile -File claude-statusline/install.ps1 -Check   # 먼저 보기 (아무것도 쓰지 않는다)
pwsh -NoProfile -File claude-statusline/install.ps1
```

- 대상: 아래 폴더의 `settings.json`. 폴더가 없으면 건너뛴다. `settings.json` 은 계정마다 따로라 모두 맞춘다.
  - `~/.claude`
  - 서브 계정 폴더 `~/<서브 계정 폴더>`: `~/.claude-*` 패턴의 폴더 중 안에 `settings.json` 이나 `.credentials.json` 이 있는 것만. 폴더 이름은 저장소에 적지 않고 패턴으로 찾는다. `~/.claude.json` 같은 파일과 빈 폴더는 빠진다.
  - `~/.agent-accounts/claude/*`
- `statusLine` 을 아래 값으로 덮어쓴다. 이미 다른 값(`padding` 등)이 있어도 바꾼다. 다른 키와 키 순서·줄바꿈(LF/CRLF)은 그대로 두고, 링크면 링크 대상에 쓴다.

```json
"statusLine": {
  "type": "command",
  "command": "pwsh -NoProfile -File <저장소>/claude-statusline/statusline.ps1"
}
```

`install.ps1` 은 pc-setup 의 **저장소 도구**다([../pc-setup/repo-tools.md](../pc-setup/repo-tools.md)). 셋업이 `-Check` 와 맞춤 실행을 대신 부른다. 손으로 돌릴 때는 저장소 루트 체크아웃에서 실행한다. 명령에 이 스크립트가 있는 폴더의 절대 경로가 들어가므로, 지울 워크트리에서 실행하지 않는다.

출력은 한 줄이다: `그대로` / `다름 (<파일>, …)`(`-Check`) / `바꿈 (<파일>, …)` / `실패: …`. 여러 파일이면 `실패` 가 먼저 보인다.

## 시험

```powershell
'{"model":{"display_name":"Opus"},"context_window":{"used_percentage":45,"total_input_tokens":90000,"context_window_size":200000}}' |
  pwsh -NoProfile -File claude-statusline/statusline.ps1
```

## 주의

- 화면 갱신은 대화가 진행될 때 일어난다. 스크립트를 고친 직후엔 바로 안 바뀔 수 있다.
- stdin 은 UTF-8 로 읽는다. `[Console]::In` 은 콘솔 코드 페이지(한국어 Windows 는 CP949)로 디코딩해 한글이 든 JSON 을 깨뜨린다.
- PowerShell 변수는 대소문자를 가리지 않는다. 색 코드용 `$E` 와 겹치는 `$e` 같은 이름을 쓰지 않는다.
