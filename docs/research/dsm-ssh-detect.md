# DSM 에서 SSH 접속을 감지하는 방법 비교

- 이슈: hdmun/anything#28 (상위 지도 #27)
- 조사일: 2026-11-06
- 범위: DSM 7.x. NAS 실물 확인은 하지 않았다. 실물 확인이 필요한 항목은 맨 끝에 모았다.
- 용어: `synology/CONTEXT.md` (브랜치 `hdmun/synology-ssh-notify`) 의 **SSH 접속**, **출발지**, **접속 알림**, **감지 장치**, **감시 시작 알림**을 쓴다.

## 결론 먼저

- **1순위: PAM `pam_exec` (session 단계)**. 연결 하나에 정확히 1번 돈다. 셸 없는 연결도 잡힌다. 사용자·**출발지**가 바로 나온다. 대신 스크립트가 끝날 때까지 접속이 기다리므로, 스크립트는 전송을 뒤로 넘기고 바로 끝나야 한다. PAM 파일을 잘못 고치면 인증이 막힐 수 있다.
- **2순위: sshd 로그 감시 (`Accepted` 줄)**. 접속 과정에 끼어들지 않으므로 접속을 늦추거나 막을 일이 없다. 대신 DSM 이 sshd 로그를 어느 파일에 남기는지 공식 문서가 없다. 감시 프로세스가 죽으면 조용히 놓친다.
- `/etc/ssh/sshrc` 와 DSM 자체 알림 기능은 맞지 않는다. 이유는 아래 각 절에 있다.
- 어느 방법이든 DSM 업데이트가 `/etc` 아래 파일을 되돌릴 수 있다(커뮤니티 보고). 그래서 **작업 스케줄러 부팅 작업**이 **감지 장치**를 확인·재설치하고 **감시 시작 알림**을 보내는 구성이 필요하다.

## 출처

| 약칭 | URL |
| --- | --- |
| [pam_exec] | https://man7.org/linux/man-pages/man8/pam_exec.8.html |
| [pam_exec.c] | https://github.com/linux-pam/linux-pam/blob/master/modules/pam_exec/pam_exec.c |
| [pam.conf] | https://man7.org/linux/man-pages/man5/pam.conf.5.html |
| [sshd.8] | https://man.openbsd.org/sshd.8 |
| [sshd_config.5] | https://man.openbsd.org/sshd_config.5 , 포터블판 `UsePAM` 항목: https://github.com/openssh/openssh-portable/blob/master/sshd_config.5 |
| [sshd-session.c] | https://github.com/openssh/openssh-portable/blob/master/sshd-session.c (8.2p1 은 `sshd.c`: https://github.com/openssh/openssh-portable/blob/V_8_2_P1/sshd.c) |
| [session.c] | https://github.com/openssh/openssh-portable/blob/master/session.c |
| [auth.c] | https://github.com/openssh/openssh-portable/blob/master/auth.c |
| [auth2.c] | https://github.com/openssh/openssh-portable/blob/master/auth2.c |
| [auth-pam.c] | https://github.com/openssh/openssh-portable/blob/master/auth-pam.c |
| [pathnames.h] | https://github.com/openssh/openssh-portable/blob/master/pathnames.h |
| [KB-Terminal] | https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/system_terminal?version=7 |
| [KB-LC-Notif] | https://kb.synology.com/en-global/DSM/help/DSM/LogCenter/logcenter_notification?version=7 |
| [KB-Webhook] | https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/system_notification_webhook?version=7 |
| [KB-Events] | https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/system_notification_filter?version=7 |
| [KB-Rules] | https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/system_notification_rule?version=7 |
| [KB-Task] | https://kb.synology.com/en-global/DSM/help/DSM/AdminCenter/system_taskscheduler?version=7 |
| [syslog-ng-program] | https://syslog-ng.github.io/admin-guide/070_Destinations/180_Program/README |
| [Syno-GA] | https://docs.synocommunity.com/packages/google-authenticator/ (SynoCommunity 패키지 문서) |
| [Syno-GA-sh] | https://github.com/SynoCommunity/spksrc/blob/master/spk/google-authenticator-libpam/src/bin/sc-google-authenticator-setup |
| [ssh-audit] | https://git.9x0rg.com/Git/ssh-audit/wiki/commit/f3567523e2808f2d047ac793e2d10aec783d3d2e (ssh-audit 위키, DSM 7.2-64570 Update 3) |
| [macdrifter] | https://www.macdrifter.com/2014/08/change-the-synology-default-ssh-port.html (2014, DSM 7 이전) |
| [nas-forum] | https://www.nas-forum.com/forum/topic/36592-plus-de-logs-ssh-dans-varlogmessages-depuis-la-43 (DSM 4.3 시절) |
| [robpickering] | https://robpickering.com/adding-custom-syslog-ng-filters-to-synology-log-center/ (DSM 7.x, 로그 센터 패키지) |
| [wazuh-dsm] | https://github.com/mjvmsteixeira/wazuh-community-rulesets (Synology DSM 디코더 샘플 로그) |
| [007revad] | https://github.com/007revad/Synology_HDD_db , https://github.com/007revad/Synology_enable_M2_card/blob/main/how_to_schedule.md |
| [netdata-gist] | https://gist.github.com/oskapt/055d474d7bfef32c49469c1b53e8225f |

표기:

- **사실**: 위 출처에 쓰여 있거나 소스 코드에서 읽은 것.
- **커뮤니티**: 공식 문서가 아니라 사용자 보고. 버전이 오래됐을 수 있다.
- **추론**: 사실을 이 프로젝트에 적용한 판단. 실물로 확인하지 않았다.

---

## 비교표

| 방법 | 1. 사용자·출발지·시각 | 2. 셸 없는 연결 | 3. 늦춤·막힘 위험 | 4. 재부팅·DSM 업데이트 |
| --- | --- | --- | --- | --- |
| PAM `pam_exec` (session) | 됨. `PAM_USER`, `PAM_RHOST`(IP). 시각은 실행 시점 | 됨. 연결마다 1번 | 스크립트가 끝날 때까지 접속이 기다림. 줄을 잘못 쓰면 인증 실패 가능 | 재부팅 후 남음(추론). 업데이트가 `/etc/pam.d/sshd` 를 되돌릴 수 있음(미확인) |
| `/etc/ssh/sshrc` | 됨. `USER`, `SSH_CONNECTION` | 부분. SFTP 는 됨, `ssh -N` 은 안 됨. 연결이 아니라 세션 채널마다 돎 | 스크립트가 끝날 때까지 기다림. stdout 에 쓰면 SFTP·scp 가 깨짐 | 위와 같음 |
| sshd 로그 감시 | 됨. `Accepted ... for 사용자 from IP port N` + 로그 시각 | 됨. 인증 성공마다 1줄 | 없음. 접속 밖에서 돎 | 스크립트는 볼륨에 두고 부팅 작업으로 띄우면 남음(추론). 로그 위치·형식은 바뀔 수 있음 |
| DSM 로그 센터 알림 | 로그 문장을 담음(추론) | 미확인 | 없음 | 남음(추론) |
| DSM 알림 웹훅 | SSH 접속 이벤트가 있는지 확인 못 함 | 미확인 | 없음 | 남음(추론) |
| 작업 스케줄러 부팅 작업 | 감지 방법이 아님. 위 방법을 다시 놓고 **감시 시작 알림**을 보내는 역할 | 해당 없음 | 없음 | 작업 자체는 남음(커뮤니티) |

---

## 1. PAM `pam_exec` (`/etc/pam.d/sshd` 의 session 단계)

예시 줄 (자리만 보임, 실물 확인 전):

```
session optional pam_exec.so quiet type=open_session /volume1/<경로>/ssh-notify.sh
```

### 사실

- **언제 도는가**: sshd 는 인증이 끝난 직후, 채널(셸·명령·SFTP)을 열기 전에 `do_pam_session()` 을 1번 부른다. [sshd-session.c] 1273-1278행. 8.2p1 의 `sshd.c` 도 같다(2236-2241행).
- `UsePAM yes` 이면 "PAM account and session module processing for all authentication types" 를 한다. 즉 공개키 로그인도 session 단계를 거친다. [sshd_config.5 포터블판]
- **얻는 값**: pam_exec 는 `PAM_RHOST`, `PAM_RUSER`, `PAM_SERVICE`, `PAM_TTY`, `PAM_USER`, `PAM_TYPE` 을 환경 변수로 넘긴다. `PAM_TYPE` 은 `open_session` 또는 `close_session` 등이다. [pam_exec]
- `PAM_RHOST` 는 `auth_get_canonical_hostname(ssh, options.use_dns)` 값이다. `UseDNS no` 이면 IP 문자열이다. [auth-pam.c] 742-750행, [auth.c] 670-680행. `UseDNS` 기본값은 `no` 다. [sshd_config.5]
- 포트 번호는 PAM 항목에 없다.
- **`type=` 옵션**: "Only run the command if the module type matches the given type." 로그아웃 때의 `close_session` 호출을 거를 수 있다. [pam_exec]
- **기다림**: pam_exec 는 `fork()` 한 뒤 `waitpid(pid, &status, 0)` 로 자식이 끝날 때까지 기다린다. 시간 제한은 없다. [pam_exec.c] 244-288행.
- 자식 쪽에서는 `setsid()` 를 부르고, `stdout` 이나 `log=` 옵션이 없으면 표준 입출력을 `/dev/null` 로 돌린다. [pam_exec.c] 335-433행, [pam_exec] ("Per default the output of the executed command is written to /dev/null.")
- **실패 처리**: `optional` 은 "the success or failure of this module is only important if it is the only module in the stack" 다. [pam.conf]
- 형식이 잘못된 줄은 "will generally tend (erring on the side of caution) to make the authentication process fail." [pam.conf]
- 줄 앞에 `-` 를 붙이면 모듈 파일이 없을 때 syslog 에 남기지 않는다. [pam.conf]
- `pam_open_session()` 이 실패하면 OpenSSH 는 연결을 끊지 않는다. 세션을 제한(`auth_restrict_session`)하고 오류만 남긴다. [auth-pam.c] `do_pam_session()`, [auth.c] `auth_restrict_session()`. 8.2p1 도 같다.
- **DSM 에서의 쓰임 (커뮤니티)**: SynoCommunity 의 Google Authenticator 패키지는 DSM 의 `/etc/pam.d/sshd` 에 줄을 더하는 방식을 쓴다. "UsePAM yes are usually already set" 라고 적는다. DSM 7.2 이상에서는 auth 단계의 `pam_syno_support.so` 가 점프를 써서 뒤의 auth 모듈을 건너뛸 수 있다고 경고한다. [Syno-GA]
- 같은 패키지의 설치 스크립트는 수정 전 백업을 만들고, `sshd -t` 로 검사하고, `synosystemctl restart sshd.service` 로 재시작한다. 자동 재적용 장치는 없고 `apply`·`undo` 명령만 있다. [Syno-GA-sh]
- 같은 문서: "A mistake in `sshd_config` or the PAM configuration can lock you out." 테스트할 때 기존 SSH 세션을 열어 두라고 한다. [Syno-GA]

### 추론

- 2번 기준(셸 없는 연결): session 단계가 채널보다 먼저, 연결마다 1번 돌기 때문에 SFTP·scp·`ssh nas 명령`·`ssh -N` 모두 1건씩 잡힌다. 지도 #27 의 "연결 하나가 1건" 과 정확히 맞는다.
- 3번 기준(늦춤): 스크립트가 직접 `curl` 을 부르면 디스코드가 느린 만큼 접속이 늦어진다. 스크립트는 값을 받아 백그라운드 작업으로 넘기고 바로 0 으로 끝나야 한다. pam_exec 가 이미 `setsid()` 를 해 주므로, 손자 프로세스는 접속이 끝나도 살아남는다.
- 3번 기준(막힘): `optional` + session 단계 + 모듈 하나만 더하면, 스크립트가 실패해도 접속은 열린다. 위험은 줄 형식을 틀리는 경우다. 그때도 DSM 웹 화면은 sshd PAM 을 쓰지 않으므로 웹으로 되돌릴 길은 남는다(추론, DSM 웹 로그인의 PAM 서비스 이름은 미확인).
- DSM 의 session 스택에 auth 단계처럼 점프가 있으면, 줄을 놓는 자리에 따라 건너뛰어질 수 있다. 실물에서 `/etc/pam.d/sshd` 전체를 봐야 한다.
- 4번 기준: 아래 "DSM 업데이트가 지우는 것" 절 참고.

---

## 2. `/etc/ssh/sshrc`, `~/.ssh/rc`

### 사실

- 로그인 순서 8단계: "If ~/.ssh/rc exists and the sshd_config(5) PermitUserRC option is set, runs it; else if /etc/ssh/sshrc exists, runs it; otherwise runs xauth(1)." [sshd.8]
- "It must not produce any output on stdout; stderr must be used instead." [sshd.8]
- `PermitUserRC` 기본값은 `yes` 다. [sshd_config.5]
- 경로는 `SSHDIR "/sshrc"`, 즉 `ETCDIR/ssh/sshrc` 다. [pathnames.h]
- **언제 도는가**: `do_child()` 안에서 사용자 권한으로 바뀐 뒤(`do_setusercontext`), 환경 변수를 만든 뒤, 셸이나 명령을 실행하기 직전에 `do_rc_files()` 를 부른다. [session.c] 1473-1598행.
- `~/.ssh/rc` 는 서브시스템(SFTP)과 관리자 강제 명령일 때 건너뛴다. `/etc/ssh/sshrc` 는 그런 조건이 없어 SFTP 에서도 돈다. 내부 SFTP 분기는 `do_rc_files()` 다음에 있다. [session.c] 1160-1201행, 1598-1609행.
- `/etc/ssh/sshrc` 는 `popen("/bin/sh /etc/ssh/sshrc", "w")` 로 돌리고 `pclose()` 로 끝날 때까지 기다린다. [session.c] 1189-1201행.
- 환경에는 `USER`, `SSH_CONNECTION`(출발지 IP·포트, 서버 IP·포트) 등이 있다. "Must take new environment into use so that .ssh/rc, /etc/ssh/sshrc and xauth are run in the proper environment." [session.c] 976, 1134, 1550-1555행 부근.
- `ChrootDirectory` 가 걸린 세션은 chroot 뒤에 돈다. [session.c] `do_setusercontext()`, [sshd_config.5]

### 추론

- 2번 기준: `do_child()` 는 세션 채널마다 돈다. 그래서 연결 하나에 채널이 여럿이면(다중화, VS Code 등) 여러 번 돌고, 채널이 없는 `ssh -N` 은 안 돈다. "연결 하나가 1건" 과 맞지 않는다.
- 사용자가 `~/.ssh/rc` 를 만들면 셸·명령 접속에서 `/etc/ssh/sshrc` 가 건너뛰어진다. 막으려면 `PermitUserRC no` 가 필요한데, 이것도 `sshd_config` 를 고치는 일이다.
- 스크립트가 **사용자 권한**으로 돈다. 디스코드 웹훅 URL 을 담은 env 파일을 모든 SSH 사용자가 읽을 수 있어야 한다. 비밀이 샌다.
- DSM 이 SFTP 사용자에게 chroot 를 건다면 chroot 안에는 `/etc/ssh/sshrc` 가 없어서 돌지 않는다. DSM 설정은 미확인.
- 3번 기준: 실수로 stdout 에 한 글자라도 쓰면 SFTP·scp 프로토콜이 깨진다. 실패해도 셸은 열리지만(반환값을 보지 않음, [session.c]), 파일 전송이 깨지는 것은 사실상 "막힘" 이다.
- 결론: 후보에서 뺀다.

---

## 3. sshd 로그 감시 (`Accepted` 줄)

### 사실

- sshd 는 인증 결과를 `"%s %s%s%s for %s%.100s from %.200s port %d ssh2%s%s"` 형식으로 남긴다. 성공이면 첫 단어가 `Accepted` 이고, 성공은 INFO 수준이다. 주소는 DNS 이름이 아니라 `ssh_remote_ipaddr()`, 즉 IP 다. [auth.c] 262-302행.
- 예: `Accepted publickey for <사용자> from 203.0.113.10 port 52144 ssh2: ED25519 SHA256:...`
- 기본값: `LogLevel INFO`, `SyslogFacility AUTH`. [sshd_config.5]
- 이 줄은 PAM account 검사 **전에** 찍힌다. account 검사에서 거부되면 `Accepted` 뒤에 연결이 끊긴다. [auth2.c] 411행(`auth_log`), 422-436행(`mm_do_pam_account`).
- syslog-ng 의 `program()` 대상은 외부 프로그램을 띄워 로그를 그 표준 입력으로 넘긴다. "If the external program exits, the syslog-ng OSE application automatically restarts it." syslog-ng 가 멈추면 프로그램도 멈춘다. 다시 읽기(reload) 때 프로그램을 유지하려면 `keep-alive()` 를 쓴다. [syslog-ng-program]

### DSM 쪽 (커뮤니티)

- DSM 4.3 부터 sshd 의 원래 `Accepted` 줄이 `/var/log/messages` 에 남지 않게 됐다는 보고가 있다. 대신 DSM 연결 로그(`/var/log/synolog/synoconn.log`)에 `User [root] from [203.0.113.10] logged in successfully via [SSH].` 형식이 남았다. 글쓴이는 `/usr/local/etc/syslog-ng/patterndb.d/` 에 설정을 더해 원래 줄을 되살렸다. [nas-forum] (IP 는 더미로 바꿈)
- 최근 Wazuh 디코더 샘플에는 `Connection: User [<사용자>] from [203.0.113.10] logged in successfully via [SSH].` 가 있다. syslog 프로그램 이름이 `Connection` 이다. [wazuh-dsm] (IP 는 더미로 바꿈)
- 로그 센터 패키지를 쓰는 환경에서는 syslog-ng 설정이 `/var/packages/LogCenter/target/etc/syslog-ng/` 아래에 있고, 패키지 업데이트가 덮어쓸 수 있다는 보고가 있다. [robpickering]

### 추론

- 1번·2번 기준: sshd `Accepted` 줄은 인증 방식과 상관없이 연결마다 1줄이고, 사용자·IP·포트·시각이 다 있다. 셸 없는 연결도 잡힌다.
- DSM `Connection:` 줄이 SFTP·`ssh nas 명령`·`ssh -N` 에도 남는지는 확인 못 했다.
- 3번 기준: 접속 과정 밖에서 돌므로 접속을 늦추거나 막지 않는다. 고장 나면 알림만 빠진다.
- `program()` 대상은 syslog-ng 가 감시 프로세스를 살려 주는 장점이 있다. 대신 DSM 의 syslog-ng 설정 파일을 고쳐야 하고, 그 파일이 업데이트로 지워질 수 있다.
- `tail -F` 로 파일을 읽는 방식은 DSM 설정을 건드리지 않는다. 대신 부팅 작업이 프로세스를 띄우고, 죽으면 다시 띄우는 장치가 따로 있어야 한다.
- 오탐: account 검사에서 거부된 연결도 `Accepted` 로 찍힌다. DSM 은 셸 로그인을 관리자 그룹만 허용하므로([KB-Terminal]) 이런 경우가 있을 수 있다. 지도 #27 범위상 "인증을 통과한 연결" 이므로 큰 문제는 아니다.
- 가장 큰 불확실성: DSM 7 기본 설정에서 sshd 원래 줄이 어느 파일에 남는지, 아예 안 남는지. 실물 확인이 먼저다.

---

## 4. DSM 자체 기능

### 사실

- **로그 센터 알림**: 심각도, 초당 로그 수, 또는 "when logs contain pre-defined keywords" 일 때 알린다. 키워드는 정규식을 쓸 수 있다. [KB-LC-Notif]
- 그런데 "Log Center notifications are sent to the address specified there", 즉 **제어판 > 알림 > 이메일** 주소로 간다. [KB-LC-Notif] (DSM 7.4 도움말 기준)
- **DSM 알림 웹훅**: 제어판 > 알림 > 웹훅에서 Custom 공급자를 만들 수 있다. POST, `application/json`, HTTP 본문에 `@@TEXT@@` 를 넣으면 이벤트 메시지로 바뀐다. [KB-Webhook]
- 웹훅은 **규칙**에 묶인다. 규칙은 DSM 시스템 이벤트 목록에서 고른다. [KB-Rules], [KB-Webhook]
- 이벤트 메시지에서 쓸 수 있는 변수는 `%HOSTNAME%`, `%IP_ADDR%`(NAS 자신의 IP), `%DATE%`, `%TIME%` 등이다. 접속한 사용자나 **출발지** 변수는 목록에 없다. [KB-Events]
- 공식 도움말 어디에도 "SSH 접속" 이벤트는 나오지 않는다. (검색으로도 찾지 못했다.)

### 추론

- 로그 센터 키워드 알림은 `logged in successfully via \[SSH\]` 같은 정규식으로 잡을 수는 있다. 하지만 이메일로만 간다. 디스코드로 가려면 메일을 받아 옮기는 다른 장치가 필요하다.
- DSM 웹훅은 디스코드 웹훅 형식(`{"content":"@@TEXT@@"}`)으로 보낼 수는 있어 보인다. 하지만 SSH 접속 이벤트가 없으면 쓸 수 없다.
- 둘 다 메시지 형식(이모지 제목 + 한 줄씩 항목), 재시도, `Retry-After` 처리를 rdp-notify 와 같게 맞출 수 없다.
- 결론: 후보에서 뺀다. 실물에서 이벤트 목록에 SSH 항목이 있는지만 확인한다.

---

## 5. 작업 스케줄러 부팅 작업과 함께 쓰기

### 사실

- 작업 스케줄러는 "Triggered tasks run before or after the completion of specific events." 사용자 정의 스크립트를 돌릴 수 있고, 실행 계정을 고를 수 있다. [KB-Task]
- 이벤트 이름(부팅 등)은 공식 도움말에 나오지 않는다.

### 커뮤니티

- 널리 쓰이는 DSM 스크립트들이 "Triggered Task → 사용자 root → 이벤트 Boot-up → 스크립트 경로" 로 설정하라고 안내한다. [007revad]
- 같은 저자: "You would need to re-run the script after a DSM update." 그래서 "the best option is to run the script every time the Synology boots." [007revad]
- DSM 6.1 이상은 `rc.local` 을 부르지 않는다. 부팅 작업으로 대신한다. [netdata-gist]

### 추론

- 부팅 작업은 감지 방법이 아니다. 역할은 셋이다. (1) **감지 장치**가 제자리에 있는지 확인하고 없으면 다시 놓는다. (2) 로그 감시 방식이면 감시 프로세스를 띄운다. (3) **감시 시작 알림**을 보낸다.
- 업데이트가 재부팅을 하면 부팅 작업이 다시 놓는다. 재부팅 없이 `/etc` 를 바꾸는 경우(제어판에서 SSH 설정 변경, 재부팅 없는 작은 업데이트가 있다면 그것)는 다음 부팅까지 빈틈이 생긴다. 주기 작업(예: 매시간)으로 같은 확인을 하면 빈틈이 줄어든다.

---

## DSM 업데이트가 지우는 것

### 커뮤니티

- "manual changes are likely overwritten by i.e. system updates or other configuration changes" — `/etc/ssh/sshd_config`, DSM 7.2-64570 Update 3. [ssh-audit]
- "DSM may regenerate `/etc/ssh/sshd_config` when SSH settings are changed in Control Panel or after a DSM update." [Syno-GA]
- DSM 업데이트가 `sshd_config` 를 되돌리는 버릇이 있다. `/etc/ssh/sshd_config` 와 `/etc.defaults/ssh/sshd_config` 를 둘 다 고쳐야 했다. [macdrifter] (2014)
- `/etc` 가 업데이트에 덮어써지는지는 모르겠고, `/usr/local/etc/rc.d` 는 안전하다는 말이 있다. [netdata-gist] (검증 안 됨)

### 확인 못 한 것

- `/etc/pam.d/sshd` 를 업데이트가 되돌린다는 직접 보고는 찾지 못했다. `sshd_config` 의 사례와 `/etc.defaults` 구조로 보아 같을 가능성이 높다(추론).
- 시놀로지 공식 문서에는 업데이트가 어떤 시스템 파일을 덮어쓰는지 나와 있지 않다. 터미널 도움말은 "Improper manipulation or modification of the Synology NAS may result in malfunctions or loss of data." 라고만 적는다. [KB-Terminal]

### 추론

- **감지 장치**의 스크립트 본체와 env 파일은 볼륨(`/volume1/...`)에 둔다. `/etc` 에는 PAM 한 줄만 둔다. 지워져도 부팅 작업이 그 한 줄만 다시 넣으면 된다.

---

## 다른 사실 (설계에 쓸 것)

- DSM 은 셸 SSH 로그인을 로컬 관리자 그룹 계정에만 허용한다. "SSH/Telnet only supports login to the system with accounts belonging to the local administrators group." [KB-Terminal]
- "Some services (e.g. network backup, SFTP) automatically enable SSH and open port 22." [KB-Terminal] → SFTP 와 네트워크 백업도 같은 sshd 를 지나므로 **SSH 접속**으로 잡힌다(추론). Hyper Backup 같은 백업 작업도 접속 알림을 만든다.

---

## NAS 실물에서 확인할 것 (#29 로 넘김)

1. `cat /etc/pam.d/sshd` 전체: session 줄 순서, `include`·점프(`[success=N]`) 여부. `pam_exec.so` 파일 위치. `ssh -V` 의 OpenSSH 버전.
2. `sshd -T` 또는 `/etc/ssh/sshd_config`: `UsePAM`, `UseDNS`, `PermitUserRC`, `ChrootDirectory`, `Match` 블록, `Subsystem sftp`.
3. sshd `Accepted` 줄과 DSM `Connection: ... logged in successfully via [SSH].` 줄이 어느 파일에 남는지(`/var/log/messages`, `/var/log/auth.log`, `/var/log/synolog/`). SFTP·`ssh nas 명령`·`ssh -N` 에도 남는지.
4. `/etc.defaults/pam.d/sshd`, `/etc.defaults/ssh/sshd_config` 가 있는지, `/etc` 사본과 다른지. syslog-ng 설정 위치와 include 구조.
5. 제어판 > 알림 > 규칙 이벤트 목록에 SSH 접속 관련 이벤트가 있는지. 작업 스케줄러 트리거 이벤트에 "부팅(Boot-up)" 이 있는지.
