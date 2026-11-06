# rdp-notify

이 PC에 원격 데스크톱으로 누군가 들어오면(새 로그온·재접속) 디스코드 채널에 접속 알림을 보낸다. PC 앞에서 직접 들어온 콘솔 접속, 로그오프, 연결 끊김, 실패한 로그인 시도는 알리지 않는다. 용어는 [CONTEXT.md](CONTEXT.md)를 따른다.

```
🖥️ RDP 접속: 재접속
PC: <PC 이름>
사용자: <PC 이름>\<사용자>
출발지: 203.0.113.10
시각: 2026-11-05 07:07:23
```

## 설치 (약 5분)

1. 디스코드 채널 설정 → 연동 → 웹후크 → 새 웹후크 → **웹후크 URL 복사**
2. `rdp-notify.env.example`을 `rdp-notify.env`로 복사하고 `DISCORD_WEBHOOK_URL=` 뒤에 붙여 넣는다
3. PowerShell을 **관리자 권한으로 실행**하고 등록한다:

   ```powershell
   & "$env:USERPROFILE\scripts\rdp-notify\register.ps1"
   ```

작업 스케줄러에 `RdpNotify`가 생긴다. 이 작업은 SYSTEM 계정으로 돌고, RDP 세션 이벤트가 기록될 때마다 `rdp-notify.ps1`을 실행한다.

## 확인

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

실행할 때마다 `logs/rdp-notify-YYYYMM.log`에 한 줄을 남긴다. 결과는 `sent`(보냄), `skipped`(RDP 접속 아님), `dryrun`(미리 보기), `error`(이벤트나 웹훅 URL 없음), `failed`(3번 시도 후 전송 실패) 중 하나다. 웹훅 URL은 남기지 않는다.

## 제거

관리자 PowerShell에서:

```powershell
& "$env:USERPROFILE\scripts\rdp-notify\register.ps1" -Unregister
```

## 파일

| 파일 | 역할 |
|---|---|
| `rdp-notify.ps1` | 이벤트 레코드 하나를 읽어 RDP 접속인지 판정하고 접속 알림을 보낸다 |
| `register.ps1` | 작업 `RdpNotify`를 등록·교체·제거한다. `-PrintXml`이면 작업 XML만 출력한다 |
| `rdp-notify.env.example` | 웹훅 URL 설정 견본 |
| `rdp-notify.env` | 실제 웹훅 URL (gitignore, 커밋하지 않는다) |

`.ps1` 파일은 UTF-8 **BOM 포함**으로 저장해야 한다. Windows PowerShell 5.1은 BOM 없는 파일의 한글을 깨뜨린다.
