# claude-statusline

Claude Code 상태 줄 스크립트다. Windows PowerShell 7 전용.

```
🤖 Opus 5.5 (medium) | 📁 anything | 🌿 main*
🧠 ██████░░░░ 62% | 124k/200k | ⏳ 7d 59% left (🔄 2d23h) | 💰 $1.23 | ⏱ 1h23m
📝 recap: 최근 recap 문구 (터미널 폭에 맞춰 자름)
```

- 1줄: 모델(effort) · 디렉터리 · git 브랜치(`*` = 변경 있음)
- 2줄: 컨텍스트 게이지 · 토큰 · 남은 사용 한도와 리셋까지 남은 시간 · 세션 과금액 · 실행 시간
- 3줄: 대화 기록(`transcript_path`)의 가장 최근 `away_summary`. 없으면 줄이 안 나온다.
- 값이 없는 항목은 빠진다. 사용량 색: 50% 미만 초록, 80% 미만 노랑, 그 이상 빨강.

## 설치

계정의 `settings.json` 에 넣는다 (계정마다 따로 — `settings.json` 은 공유되지 않는다):

```json
"statusLine": {
  "type": "command",
  "command": "pwsh -NoProfile -File C:/workspace/anything/claude-statusline/statusline.ps1"
}
```

## 시험

```powershell
'{"model":{"display_name":"Opus"},"context_window":{"used_percentage":45,"total_input_tokens":90000,"context_window_size":200000}}' |
  pwsh -NoProfile -File claude-statusline/statusline.ps1
```

## 주의

- 화면 갱신은 대화가 진행될 때 일어난다. 스크립트를 고친 직후엔 바로 안 바뀔 수 있다.
- stdin 은 UTF-8 로 읽는다. `[Console]::In` 은 콘솔 코드 페이지(한국어 Windows 는 CP949)로 디코딩해 한글이 든 JSON 을 깨뜨린다.
- PowerShell 변수는 대소문자를 가리지 않는다. 색 코드용 `$E` 와 겹치는 `$e` 같은 이름을 쓰지 않는다.
