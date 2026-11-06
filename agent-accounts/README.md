# agent-accounts

`claude`·`codex` 를 개인 계정 여러 개로 나눠 쓴다. 계정마다 `<cli>-<계정>` 명령(예: `claude-sub`, `codex-alt`)이 생기고, 각자 따로 로그인한다. 그냥 `claude`·`codex` 는 지금 계정 그대로다.

- 로그인 정보·대화 기록은 계정마다 따로: `~/.agent-accounts/<cli>/<계정>`
- `CLAUDE.md`·`skills` 등은 기본 계정 것을 링크로 함께 쓴다 (폴더=junction, 파일=symlink)
- Windows PowerShell 7 전용. agy 는 지원하지 않는다 (토큰이 Windows 자격 증명 관리자 한 항목에 고정돼 나눌 수 없다).

## 설치 (1분)

1. 프로필에 한 줄 넣는다:

   ```powershell
   Add-Content $PROFILE '. "$env:USERPROFILE\scripts\agent-accounts\AgentAccounts.ps1"'
   ```

2. 새 PowerShell 창을 연다. 처음 불러올 때 `accounts.example.psd1` 이 `accounts.psd1` 로 복사된다 (git 에 안 올라감).

## 계정 추가

```powershell
Add-AgentAccount claude sub    # claude-sub 생김
claude-sub                     # 첫 실행에서 로그인
```

계정 이름은 영문·숫자·`_` 만 된다.

## 상태 확인

```powershell
Get-AgentAccount
```

`LoggedIn` 이 `False` 면 아직 로그인 전이다. `Missing` 에 이름이 있으면 공유 링크가 빠진 것이다: `Add-AgentAccount <cli> <계정>` 을 다시 실행하면 채워진다.

## 계정 제거

1. `accounts.psd1` 의 `Accounts` 에서 이름을 지운다.
2. 폴더를 지운다. **PowerShell 7 에서** 지운다 (링크만 지워지고 원본은 남는다):

   ```powershell
   Remove-Item -Recurse -Force "$HOME\.agent-accounts\claude\sub"
   ```

## 새 CLI 추가

`accounts.psd1` 의 `Clis` 에 항목 하나를 더한다. CLI 가 설정 폴더를 환경변수로 바꿀 수 있어야 한다. 항목 설명은 `accounts.example.psd1` 주석을 본다.

## 주의

- `settings.json`(claude)·`config.toml`(codex)은 공유하지 않는다. 계정마다 따로 고친다.
- 기존 `~/.claude-max` 는 이 도구와 관계없이 그대로 둔다.
