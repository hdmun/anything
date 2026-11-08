# synology: ssh-notify

시놀로지 NAS 에 누군가 SSH 로 들어오면 디스코드 채널에 접속 알림을 보낸다. 셸·명령 실행·`ssh -N`·`scp -O` 모두 연결 하나마다 1건이다. 내 접속도 알린다. 실패한 로그인 시도, 로그아웃, 연결 끊김은 알리지 않는다. 용어는 [CONTEXT.md](CONTEXT.md)를 따른다.

```
🔐 SSH 접속
NAS: <NAS 이름>
사용자: <계정>
출발지: 203.0.113.10
시각: 2026-11-08 09:12:29
```

감지 장치가 돌기 시작할 때마다 감시 시작 알림도 1건 보낸다. 이유는 세 가지다.

- `부팅`: NAS 를 켰다.
- `설치`: 사람이 감지 장치를 새로 올렸다.
- `다시 시작`: 감지 장치가 멈췄다가 다시 돌았다. 무언가 고장 났다는 신호다.

NAS 를 켠 뒤 이 알림이 오지 않으면 감시가 멈춘 것이다.

```
👀 SSH 감시 시작: 부팅
NAS: <NAS 이름>
시각: 2026-11-08 09:00:05
```

감지 장치는 SSH 접속 경로 밖에서 sshd 의 journal 을 읽기만 한다. 그래서 알림이 느리거나 실패해도 SSH 접속은 늦어지거나 막히지 않는다. `/etc` 의 설정은 하나도 고치지 않는다. 감지 장치가 멈춘 동안 들어온 접속은 다시 돌기 시작할 때 늦게 알린다. 늦게 보낸 알림의 시각은 실제 접속 시각이다.

## 설치 (약 15분)

준비물: 이 PC 에서 `ssh <별칭>` 으로 NAS 에 들어갈 수 있어야 한다. `<별칭>` 은 `~/.ssh/config` 의 NAS 항목이다. NAS 계정의 sudo 비밀번호도 필요하다.

1. 디스코드 채널 설정 → 연동 → 웹후크 → 새 웹후크 → **웹후크 URL 복사**
2. env 파일을 만든다. 열린 메모장에서 `DISCORD_WEBHOOK_URL=` 뒤의 견본 URL 을 복사한 URL 로 바꾸고 저장한다:

   ```powershell
   cd "$env:USERPROFILE\scripts\synology"
   Copy-Item ssh-notify.env.example ssh-notify.env
   notepad ssh-notify.env
   ```

3. 같은 창에서 NAS 에 올린다. 중간에 `[sudo] password for <계정>:` 이 나오면 NAS 계정 비밀번호를 넣는다:

   ```powershell
   .\deploy.ps1 -Host <별칭>
   ```

   `설치했다. 디스코드에 '설치' 감시 시작 알림이 왔는지 본다.` 가 나오면 성공이다. 디스코드에 `👀 SSH 감시 시작: 설치` 가 온다.
4. DSM 작업 스케줄러에 작업 2개를 만든다. 처음 한 번만 한다. 다시 올려도 작업은 고치지 않는다. 화면 이름은 DSM 버전마다 조금 다를 수 있다.
   - [ ] DSM 에 관리자로 로그인 → **제어판** → **작업 스케줄러**
   - [ ] **생성** → **트리거된 작업** → **사용자 정의 스크립트**
     - 일반: 작업 이름 `ssh-notify 부팅`, 사용자 `root`, 이벤트 `부트업`, 활성화 체크
     - 작업 설정 → 사용자 정의 스크립트: `/usr/bin/python3 /volume1/@ssh-notify/ssh-notify.py`
     - **확인**. root 작업 경고가 나오면 **확인**
   - [ ] **생성** → **예약된 작업** → **사용자 정의 스크립트**
     - 일반: 작업 이름 `ssh-notify 매시간`, 사용자 `root`, 활성화 체크
     - 일정: **매일 실행**, 첫 실행 시간 `00:00`, 빈도 **매 1 시간**, 마지막 실행 시간 `23:00`
     - 작업 설정 → 사용자 정의 스크립트: 위와 같은 한 줄
     - **확인**
   - [ ] 목록에 두 작업이 보이고 사용자가 `root` 다

이제 감지 장치는 다음처럼 돈다.

- NAS 를 켜면 `ssh-notify 부팅` 이 감지 장치를 띄운다.
- `ssh-notify 매시간` 은 감지 장치가 멈춰 있으면 다시 띄운다. 이미 돌고 있으면 아무것도 하지 않고 끝난다.

## 실제 시험

설치한 뒤 이 순서로 확인한다. 약 25분 걸리고, 재부팅에 5분이 더 든다.

1. **접속 1건**: 다른 창에서 `ssh <별칭> true`. 몇 초 안에 디스코드에 `🔐 SSH 접속` 이 온다. NAS 이름·사용자·출발지·시각이 맞고 한글이 깨지지 않아야 한다.
2. **멈춤 → 다시 시작**
   1. 감지 장치를 멈춘다: `ssh -t <별칭> sudo python3 /volume1/@ssh-notify/ssh-notify.py --stop`
   2. 멈춘 동안 `ssh <별칭> true` 로 1번 접속한다. 알림이 오지 않아야 한다.
   3. DSM 작업 스케줄러에서 `ssh-notify 매시간` 을 고르고 **실행**한다.
   4. `👀 SSH 감시 시작: 다시 시작` 이 오고, 바로 뒤에 2번에서 한 접속의 알림이 온다. 시각은 2번에서 접속한 시각이다.
3. **다시 올리기**: `.\deploy.ps1 -Host <별칭>` 을 한 번 더 실행한다. `설치` 알림만 와야 하고, 이미 보낸 접속 알림이 다시 오면 안 된다.
4. **재부팅**: DSM 에서 NAS 를 다시 시작한다. 켜진 뒤 `👀 SSH 감시 시작: 부팅` 이 온다. 이어서 `ssh <별칭> true` 를 하면 접속 알림이 온다.
5. **제거 → 다시 설치**: [제거](#제거) 2번만 하고 DSM 작업은 그대로 둔다.
   1. `ssh <별칭> ls /volume1/@ssh-notify` 가 `No such file or directory` 를 내야 한다.
   2. `.\deploy.ps1 -Host <별칭>` 으로 다시 설치한다. `설치` 알림 1건만 와야 하고, 시험하며 쌓인 지난 접속 알림이 오면 안 된다.

DSM 업데이트 뒤에도 계속 도는지는 지금 시험할 수 없다. 다음 DSM 업데이트로 NAS 가 다시 켜지면 `부팅` 알림이 오는지 본다.

## 미리 보기

journal 줄로 보낼 메시지를 화면에만 찍는다. 보내지 않고 아무것도 저장하지 않는다.

```powershell
# PC: 저장소의 견본 줄로 (PowerShell 에는 < 가 없어서 Get-Content 로 넘긴다)
cd "$env:USERPROFILE\scripts\synology"
Get-Content testdata\sshd-journal.jsonl | python ssh-notify.py --preview
```

```sh
# NAS: 실제 journal 의 최근 sshd 줄 20개로 ("이 접속은 왜 알림이 안 왔지?" 확인용, root 만 journal 을 읽는다)
sudo journalctl -o json _COMM=sshd -n 20 | python3 /volume1/@ssh-notify/ssh-notify.py --preview
```

## 로그

감지 장치는 `/volume1/@ssh-notify/logs/ssh-notify-YYYYMM.log` 에 한 줄씩 남긴다. sudo 없이 읽힌다. 최근 5줄 보기:

```powershell
ssh <별칭> "tail -n 5 /volume1/@ssh-notify/logs/*.log"
```

```
2026-11-08 09:00:05 sent kind=start reason=boot attempts=1
2026-11-08 09:12:30 sent kind=access user=<계정> src=203.0.113.10 at=2026-11-08T09:12:29 attempts=1
2026-11-08 09:20:41 failed kind=access user=<계정> src=203.0.113.10 attempts=3 error=HTTP Error 404
2026-11-08 09:30:00 journal-exit code=1 wait=5
2026-11-08 09:31:00 error reason=no-webhook-url
```

- 결과 값
  - `sent`: 보냈다.
  - `failed`: 3번 시도한 뒤에도 못 보냈다. 기록만 하고 다음으로 넘어간다.
  - `journal-exit`: journalctl 이 끝났다. `wait` 초 뒤에 다시 띄운다.
  - `error`: 감지 장치가 멈췄다.
- `kind` 값: `access` 는 접속 알림, `start` 는 감시 시작 알림이다.
- `reason` 값: `boot`(부팅), `restart`(다시 시작), `install`(설치), 또는 `error` 의 원인이다.
- 로그에는 출발지 IP 가 남는다. 웹훅 URL 은 남지 않는다. `Accepted` 가 아닌 sshd 줄과, 매시간 작업이 "이미 돌고 있음"으로 끝난 경우는 남기지 않는다.

감지 장치가 도는지 보기:

```powershell
ssh <별칭> "ps -ef | grep '[s]sh-notify.py --run'"
```

## 문제 해결

| 증상 | 원인과 해결 |
|---|---|
| `deploy.ps1` 이 `웹훅 URL 이 없다` 를 낸다 | `ssh-notify.env` 가 없거나 견본 URL 그대로다. [설치](#설치-약-15분) 2번을 다시 한다 |
| `deploy.ps1` 이 `줄 끝이 CRLF 다` 를 낸다 | 저장소 최상위에서 `git add --renormalize synology` 를 하고 파일을 다시 체크아웃한다. `.gitattributes` 가 `synology/*.sh`·`*.py` 를 LF 로 둔다 |
| `NAS 로 올리지 못했다` | `ssh <별칭> true` 가 되는지 본다. 별칭이 `~/.ssh/config` 에 있어야 한다 |
| `sudo` 비밀번호를 틀렸다 | `deploy.ps1` 을 다시 실행한다. 이미 올린 파일은 다시 올라간다 |
| 설치 끝에 `감시 시작 알림을 보내지 못했다` | 위의 로그 줄을 본다. `error=HTTP Error 404` 면 웹훅이 지워졌거나 URL 이 틀렸다. env 를 고치고 다시 올린다 |
| `50초 안에 로그에 감시 시작 기록이 없다` | `journal-exit` 줄이 있으면 journalctl 이 계속 끝나는 것이다. NAS 에서 `sudo journalctl -f _COMM=sshd` 가 되는지 본다 |
| 재부팅 뒤 `부팅` 알림이 안 온다 | `ssh-notify 부팅` 작업이 있고 사용자가 `root`, 이벤트가 `부트업`, 활성화돼 있는지 본다. DSM 업데이트가 작업을 지웠을 수 있다. 그동안의 접속은 감지 장치가 다시 돌면 늦게 알린다 |
| `다시 시작` 알림이 왔다 | 감지 장치가 멈췄었다. 로그의 `error reason=crash` 줄에서 원인을 본다 |
| DSM 작업을 실행해도 감지 장치가 곧 사라진다 | 위의 "감지 장치가 도는지 보기" 로 확인하고, 로그의 마지막 `error` 줄을 본다 |
| 알림이 너무 많다 | 자동 SSH 터널이 다시 접속할 때마다 알린다. 터널이 끊겼다는 신호다. 줄이려면 따로 이슈를 만든다 |

## 바꿀 때

- `ssh-notify.py` 를 고치면 `.\deploy.ps1 -Host <별칭>` 으로 다시 올린다. `설치` 알림이 오면 새 파일로 돌고 있다. DSM 작업은 고치지 않는다.
- 시험: `cd synology` 뒤 `python -m unittest`. NAS 의 `python3` 는 3.8 이므로 3.9 이상에서만 되는 문법·함수를 쓰지 않는다. 예: `match`, `X | Y` 타입, `str.removeprefix`, `zoneinfo`. 큰 변경 뒤에는 시험 파일을 NAS 의 홈 폴더에 올려 `python3 -m unittest` 로도 돌린다.
- `.py`·`.sh` 는 LF 로 둔다. `deploy.ps1` 은 UTF-8 **BOM 포함**으로 저장한다. Windows PowerShell 5.1 은 BOM 없는 파일의 한글을 깨뜨린다.
- NAS 주소·계정·웹훅 URL 은 저장소에 쓰지 않는다. 공개 저장소다.

## 제거

1. DSM 작업 스케줄러에서 `ssh-notify 부팅`·`ssh-notify 매시간` 을 지운다. 빠뜨려도 해는 없다. 매시간 작업이 "파일 없음"으로 실패할 뿐이다.
2. PC 에서 아래 명령을 실행하고 sudo 비밀번호를 넣는다. `/volume1/@ssh-notify/` 가 로그·cursor 까지 통째로 지워진다. 로그가 필요하면 먼저 복사한다.

   ```powershell
   cd "$env:USERPROFILE\scripts\synology"
   .\deploy.ps1 -Host <별칭> -Remove
   ```

## 파일

| 파일 | 역할 |
|---|---|
| `ssh-notify.py` | 감지 장치. journal 의 sshd 줄을 읽어 접속 알림·감시 시작 알림을 보낸다. `--install`·`--stop`·`--preview` |
| `install.sh` | NAS 에서 root 로 설치·다시 올리기·제거(`--remove`) |
| `deploy.ps1` | PC 에서 파일을 올리고 `install.sh` 를 부른다 |
| `ssh-notify.env.example` | 웹훅 URL 설정 견본 |
| `ssh-notify.env` | 실제 웹훅 URL (gitignore, 커밋하지 않는다) |
| `test_ssh_notify.py` | `unittest` 시험 |
| `testdata/sshd-journal.jsonl` | `journalctl -o json` 모양의 견본 줄 (더미 값) |

NAS 에 설치되는 곳:

```
/volume1/@ssh-notify/            root 755   공유 폴더가 아니라 File Station·SMB 에 안 보인다
├─ ssh-notify.py                 root 755
├─ ssh-notify.env                root 600
├─ state/                        root 700   cursor.json (어디까지 읽었나), lock, pid
└─ logs/ssh-notify-YYYYMM.log    root 644
```
