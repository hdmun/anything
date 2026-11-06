# rdp-notify

이 PC에 원격 데스크톱으로 누군가 들어오면(새 로그온·재접속) 디스코드 채널에 접속 알림을 보낸다. PC 앞에서 직접 들어온 콘솔 접속, 로그오프, 연결 끊김, 실패한 로그인 시도는 알리지 않는다. 용어는 [CONTEXT.md](CONTEXT.md)를 따른다.

```
🖥️ RDP 접속: 재접속
PC: <PC 이름>
사용자: <PC 이름>\<사용자>
출발지: 203.0.113.10
시각: 2026-11-05 07:07:23
```

출발지는 접속을 건 기기의 IP 주소다. 같은 공유기 안에서 접속하면 기기 주소 대신 공유기 주소로 보일 수 있다.

## 설치 (약 5분)

1. 디스코드 채널 설정 → 연동 → 웹후크 → 새 웹후크 → **웹후크 URL 복사**
2. env 파일을 만든다. 열린 메모장에서 `DISCORD_WEBHOOK_URL=` 뒤의 견본 URL을 복사한 URL로 바꾸고 저장한다:

   ```powershell
   cd "$env:USERPROFILE\scripts\rdp-notify"
   Copy-Item rdp-notify.env.example rdp-notify.env
   notepad rdp-notify.env
   ```

3. 관리자 PowerShell을 연다: `Win + X` → **터미널(관리자)** → "이 앱이 디바이스를 변경하도록 허용하시겠어요?"에서 **예**. 창 제목에 "관리자"가 있어야 한다.
4. 관리자 창에서 등록한다. 두 줄을 그대로 붙여 넣는다:

   ```powershell
   cd "$env:USERPROFILE\scripts\rdp-notify"
   .\register.ps1
   ```

   `작업 RdpNotify 을 등록했다. ...`가 나오면 성공이다.
5. 같은 관리자 창에서 등록 상태를 확인한다. `State`가 `Ready`, `User`가 `SYSTEM`이면 정상이다:

   ```powershell
   Get-ScheduledTask RdpNotify | Select-Object TaskName, State, @{ n = 'User'; e = { $_.Principal.UserId } }
   ```

이제 작업 스케줄러의 `RdpNotify` 작업이 SYSTEM 계정으로, RDP 세션 이벤트가 기록될 때마다 `rdp-notify.ps1`을 실행한다.

## 실제 시험

1. 다른 기기(휴대폰 Windows App, 다른 PC)에서 이 PC로 RDP 접속한다. 같은 PC에서 자기 자신으로는 접속할 수 없다.
2. 몇 초 안에 디스코드에 알림이 온다. PC 앞 세션을 이어받으면 종류는 `재접속`이다.
3. RDP 연결을 끊고 PC 앞에서 다시 로그인한다. 콘솔 접속이라 알림이 오지 않아야 정상이다.
4. [로그](#로그) 마지막 두 줄이 `sent`와 `skipped ... src=LOCAL`인지 본다.

## 미리 보기

과거 이벤트 하나로 메시지를 미리 본다. 보내지는 않는다.

```powershell
# 최근 RDP 세션 이벤트의 RecordId 를 찾는다 (21 새 로그온, 25 재접속)
Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'; Id = 21, 25 } -MaxEvents 5 |
    Select-Object TimeCreated, Id, RecordId

# 그중 하나로 미리 보기 (-DryRun 을 빼면 실제로 보낸다)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\scripts\rdp-notify\rdp-notify.ps1" -RecordId <RecordId> -DryRun
```

작업 스케줄러에서 `RdpNotify`를 직접 "실행"하면 `$(RecordId)` 값이 채워지지 않아 실패한다. 수동으로 확인할 때는 위처럼 스크립트를 바로 실행한다.

## 로그

실행할 때마다 `logs/rdp-notify-YYYYMM.log`에 한 줄을 남긴다. 최근 5줄 보기:

```powershell
Get-Content "$env:USERPROFILE\scripts\rdp-notify\logs\rdp-notify-$(Get-Date -Format yyyyMM).log" -Tail 5
```

- 결과 값: `sent`(보냄), `skipped`(RDP 접속 아님), `dryrun`(미리 보기), `error`(이벤트나 웹훅 URL 없음), `failed`(3번 시도 후 전송 실패)
- 출발지 IP가 남는다. `*.log`는 gitignore 대상이라 커밋되지 않는다. 웹훅 URL은 남기지 않는다.
- 작업 실행 기록(`Get-ScheduledTaskInfo`)은 관리자 창에서만 보인다. 일반 창에서는 이 로그로 확인한다.

## 문제 해결

| 증상 | 원인과 해결 |
|---|---|
| `관리자 권한이 필요하다...` | 관리자 창이 아니다. [설치](#설치-약-5분) 3번으로 창을 다시 연다 |
| `식 또는 문에서 예기치 않은 '\scripts\...' 토큰입니다` | `$env:USERPROFILE\...` 경로를 `&`와 따옴표 없이 입력했다. 설치 4번의 `cd` 두 줄을 쓴다 |
| `Get-ScheduledTask`에서 `'RdpNotify'와(과) 같은 MSFT_ScheduledTask 개체를 찾을 수 없습니다` | 일반 창에서는 SYSTEM 작업이 보이지 않는다. 관리자 창에서 실행한다 |
| `Get-ScheduledTaskInfo`에서 `액세스가 거부되었습니다` | 일반 창이다. 로그로 확인하거나 관리자 창에서 실행한다 |
| 알림이 안 오고 로그 마지막 줄이 `error ... reason=no-webhook-url` | `rdp-notify.env`가 없거나 URL 줄이 틀렸다. 설치 2번을 다시 한다 |
| 알림이 안 오고 로그 마지막 줄이 `failed` | 네트워크 문제거나 웹훅이 지워졌다. `error=` 뒤의 메시지를 본다 |
| 알림이 안 오고 로그에 새 줄이 없다 | 작업이 등록되지 않았다. 관리자 창에서 설치 5번으로 확인한다 |

## 바꿀 때

- `rdp-notify.ps1`을 고치면 다시 등록하지 않아도 다음 접속부터 반영된다.
- `register.ps1`을 고쳤거나 저장소 폴더를 옮겼으면 `register.ps1`을 다시 실행한다. 작업에 스크립트의 절대 경로가 들어 있다.
- `.ps1` 파일은 UTF-8 **BOM 포함**으로 저장한다. Windows PowerShell 5.1은 BOM 없는 파일의 한글을 깨뜨린다.

## 제거

관리자 창에서:

```powershell
cd "$env:USERPROFILE\scripts\rdp-notify"
.\register.ps1 -Unregister
```

## 파일

| 파일 | 역할 |
|---|---|
| `rdp-notify.ps1` | 이벤트 레코드 하나를 읽어 RDP 접속인지 판정하고 접속 알림을 보낸다 |
| `register.ps1` | 작업 `RdpNotify`를 등록·교체·제거한다. `-PrintXml`이면 작업 XML만 출력한다 |
| `rdp-notify.env.example` | 웹훅 URL 설정 견본 |
| `rdp-notify.env` | 실제 웹훅 URL (gitignore, 커밋하지 않는다) |
