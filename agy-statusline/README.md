# agy-statusline

Antigravity CLI(`agy`) 상태 줄 스크립트다. Windows 는 `statusline.ps1`(PowerShell 7), macOS 는 `statusline.sh`(bash 3.2 + jq 1.7)를 쓴다. 두 스크립트는 같은 출력을 낸다.

```
🤖 Gemini 4 Neon (medium) | 📁 anything | 🌿 hdmun/agy-statusline*
🧠 ██████░░░░ 62% | 124k/1M | ⏳ 5h 2% (🔄 4h29m)  7d 1% (🔄 6d23h) | 💰 $0.42
📝 recap: 대화 제목 요약 (터미널 폭에 맞춰 자름)
```

- 1줄: 모델(effort) · 디렉터리 · git 브랜치(`*` = 변경 있음)
- 2줄: 컨텍스트 게이지 · 토큰 · 사용 한도의 쓴 %와 리셋까지 남은 시간(`quota`) · 예상 과금액(`cost.total_usd`)
  - 세션 실행 시간은 agy 입력 JSON에 없어 생략한다.
- 3줄: 대화 제목(`conversation_title`). 없으면 줄이 안 나온다.
- 사용 한도는 세션 첫 응답 전에는 입력에 없다. 그때는 마지막 값을 캐시에서 읽어 보인다(리셋 시각이 지난 창은 0%, 리셋 시간 없음). 캐시: `~/.gemini/antigravity-cli/statusline-quota.json`.
- 값이 없는 항목은 빠진다. 컨텍스트·사용량 색(쓴 % 기준): 50% 미만 초록, 80% 미만 노랑, 그 이상 빨강.

## 설치

### Windows

```powershell
pwsh -NoProfile -File agy-statusline/install.ps1 -Check   # 먼저 보기 (아무것도 쓰지 않는다)
pwsh -NoProfile -File agy-statusline/install.ps1
```

- 대상: `~/.gemini/antigravity-cli/settings.json`. 폴더가 없으면 건너뛴다.
- `statusLine` 을 아래 값으로 덮어쓴다. 이미 다른 값이 있어도 바꾼다. 다른 키와 키 순서·줄바꿈은 그대로 두고, 링크면 링크 대상에 쓴다.

```json
"statusLine": {
  "type": "command",
  "command": "pwsh -NoProfile -File <저장소>/agy-statusline/statusline.ps1"
}
```

`install.ps1` 은 pc-setup 의 **저장소 도구**다([../pc-setup/repo-tools.md](../pc-setup/repo-tools.md)). 셋업이 `-Check` 와 맞춤 실행을 대신 부른다. 손으로 돌릴 때는 저장소 루트 체크아웃에서 실행한다. 명령에 이 스크립트가 있는 폴더의 절대 경로가 들어가므로, 지울 워크트리에서 실행하지 않는다.

출력은 한 줄이다: `그대로` / `다름 (<파일>, …)`(`-Check`) / `바꿈 (<파일>, …)` / `실패: …`. 여러 파일이면 `실패` 가 먼저 보인다.

### macOS

```sh
bash agy-statusline/install.sh --check   # 먼저 보기 (아무것도 쓰지 않는다)
bash agy-statusline/install.sh
```

- 대상·덮어쓰기 규칙·출력 한 줄은 Windows 와 같다. 홈 폴더 대신 다른 폴더를 보려면 `--home <dir>` 을 붙인다(시험용).
- `statusLine` 값:

```json
"statusLine": {
  "type": "command",
  "command": "bash <저장소>/agy-statusline/statusline.sh"
}
```

- 설정 파일을 바꾸지 않고 한 세션에서만 써 보려면 `agy --settings '{"statusLine":{"type":"command","command":"bash <저장소>/agy-statusline/statusline.sh"}}'` 로 띄운다.

TUI 안에서 `/statusline` 명령으로 켜고 끌 수 있다 (`/statusline on`, `/statusline off`, `/statusline delete`).

## 시험

Windows:

```powershell
'{"model":{"id":"Gemini 4 Neon (Medium)","display_name":"Gemini 4 Neon (Medium)","effort":"medium"},"workspace":{"current_dir":"C:/workspace/anything"},"context_window":{"used_percentage":45,"total_input_tokens":90000,"context_window_size":1048576}}' |
  pwsh -NoProfile -File agy-statusline/statusline.ps1
```

macOS:

```sh
echo '{"model":{"id":"Gemini 4 Neon (Medium)","display_name":"Gemini 4 Neon (Medium)","effort":"medium"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"used_percentage":45,"total_input_tokens":90000,"context_window_size":1048576}}' |
  bash agy-statusline/statusline.sh
bash agy-statusline/test.sh   # 임시 HOME 으로 install.sh 와 statusline.sh 를 시험한다
```

## 주의

- agy는 에이전트 상태가 바뀔 때 최대 300ms 간격으로 스크립트를 실행하며, 5초를 넘기면 중단한다. 30회 연속 실패하면 세션 동안 상태 줄이 꺼진다.
- PowerShell 변수는 대소문자를 가리지 않는다. 색 코드용 `$E` 와 겹치는 `$e` 같은 이름을 쓰지 않는다.
- `statusline.sh` 는 부를 때마다 외부 명령을 jq 2번, git 1번(분리된 HEAD 면 2번)만 부른다. 한 번에 수십 ms 안에 끝난다.
- macOS 의 `/bin/bash` 는 3.2 다. bash 4 기능을 쓰지 않는다. 시간대가 없는 `reset_time` 은 로컬 시각으로 읽는다.
