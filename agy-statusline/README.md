# agy-statusline

Antigravity CLI(`agy`) 상태 줄 스크립트다. Windows PowerShell 7 전용.

```
🤖 Gemini 4 Neon (medium) | 📁 anything | 🌿 hdmun/agy-statusline*
🧠 ██████░░░░ 62% | 124k/1M | ⏳ 5h 98% left (🔄 4h29m)  7d 99% left (🔄 6d23h) | 💰 $0.42
📝 recap: 대화 제목 요약 (터미널 폭에 맞춰 자름)
```

- 1줄: 모델(effort) · 디렉터리 · git 브랜치(`*` = 변경 있음)
- 2줄: 컨텍스트 게이지 · 토큰 · 남은 사용 한도와 리셋까지 남은 시간(`quota`) · 예상 과금액(`cost.total_usd`)
  - 세션 실행 시간은 agy 입력 JSON에 없어 생략한다.
- 3줄: 대화 제목(`conversation_title`). 없으면 줄이 안 나온다.
- 값이 없는 항목은 빠진다. 사용량 색: 50% 미만 초록, 80% 미만 노랑, 그 이상 빨강.

## 설치

`~/.gemini/antigravity-cli/settings.json` 에 넣는다:

```json
"statusLine": {
  "type": "command",
  "command": "pwsh -NoProfile -File C:/workspace/anything/agy-statusline/statusline.ps1"
}
```

TUI 안에서 `/statusline` 명령으로 켜고 끌 수 있다 (`/statusline on`, `/statusline off`, `/statusline delete`).

## 시험

```powershell
'{"model":{"id":"Gemini 4 Neon (Medium)","display_name":"Gemini 4 Neon (Medium)","effort":"medium"},"workspace":{"current_dir":"C:/workspace/anything"},"context_window":{"used_percentage":45,"total_input_tokens":90000,"context_window_size":1048576}}' |
  pwsh -NoProfile -File agy-statusline/statusline.ps1
```

## 주의

- agy는 에이전트 상태가 바뀔 때 최대 300ms 간격으로 스크립트를 실행하며, 5초를 넘기면 중단한다. 30회 연속 실패하면 세션 동안 상태 줄이 꺼진다.
- PowerShell 변수는 대소문자를 가리지 않는다. 색 코드용 `$E` 와 겹치는 `$e` 같은 이름을 쓰지 않는다.
