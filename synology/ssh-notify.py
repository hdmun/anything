#!/usr/bin/env python3
"""ssh-notify: 시놀로지 NAS 의 SSH 접속을 journal 에서 알아채 디스코드 웹훅으로 알린다.

용어는 synology/CONTEXT.md 를 따른다. NAS 의 python3 가 3.8.12 이므로 3.8 문법만 쓴다.

    python3 ssh-notify.py              # 감지 장치를 백그라운드로 띄운다 (DSM 작업 2개)
    python3 ssh-notify.py --install    # 위와 같고 시작 이유를 '설치'로 한다 (install.sh)
    python3 ssh-notify.py --stop       # 돌고 있는 감지 장치를 멈춘다 (root)
    python3 ssh-notify.py --preview < 줄파일   # journal JSON 줄로 보낼 메시지를 화면에만 찍는다
"""
import argparse
import datetime
import json
import math
import os
import re
import signal
import socket
import subprocess
import sys
import time
import urllib.request

REASON_INSTALL = "설치"
REASON_BOOT = "부팅"
REASON_RESTART = "다시 시작"
REASON_LOG = {REASON_INSTALL: "install", REASON_BOOT: "boot", REASON_RESTART: "restart"}

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(BASE_DIR, "ssh-notify.env")
STATE_DIR = os.path.join(BASE_DIR, "state")
LOG_DIR = os.path.join(BASE_DIR, "logs")
STATE_PATH = os.path.join(STATE_DIR, "cursor.json")
LOCK_PATH = os.path.join(STATE_DIR, "lock")
PID_PATH = os.path.join(STATE_DIR, "pid")
BOOT_ID_PATH = "/proc/sys/kernel/random/boot_id"
JOURNALCTL = "/usr/bin/journalctl"

USER_AGENT = "ssh-notify"
MAX_ATTEMPTS = 3
ATTEMPT_TIMEOUT_SECONDS = 10
DEFAULT_RETRY_SECONDS = 5
MAX_RETRY_SECONDS = 60
STARTUP_CHECK_SECONDS = 2
RESTART_WAIT_MIN_SECONDS = 5
RESTART_WAIT_MAX_SECONDS = 300
HEALTHY_RUN_SECONDS = 60
STOP_WAIT_SECONDS = 10

# 줄 맨 앞에서만 맞춘다. 실패 줄의 사용자 이름 자리에 이 문구를 넣어도 SSH 접속으로 보지 않는다.
ACCEPTED_RE = re.compile(r"^Accepted (\S+) for (\S+) from (\S+) port (\d+)")
WEBHOOK_RE = re.compile(r"""^\s*DISCORD_WEBHOOK_URL\s*=\s*["']?(https://[^"'\s]+)["']?\s*$""")


# ---------------------------------------------------------------- 판정·메시지 (순수 함수)

def message_text(entry):
    """journal 항목의 MESSAGE 를 문자열로 돌려준다. 숫자 배열이면 바이트로 보고 UTF-8 로 푼다."""
    value = entry.get("MESSAGE")
    if isinstance(value, list):
        return bytes(value).decode("utf-8", errors="replace")
    if isinstance(value, str):
        return value
    return ""


def parse_access(message):
    """SSH 접속 줄이면 {"user", "source"} 를, 아니면 None 을 돌려준다."""
    match = ACCEPTED_RE.match(message)
    if not match:
        return None
    return {"user": match.group(2), "source": match.group(3)}


def access_time(entry, tz=None):
    """journal 에 남은 실제 접속 시각. tz 가 None 이면 NAS 의 시간대를 쓴다."""
    seconds = int(entry["__REALTIME_TIMESTAMP"]) // 1000000
    return datetime.datetime.fromtimestamp(seconds, tz)


def format_access_message(host, user, source, when):
    """접속 알림 본문."""
    return "\n".join([
        "🔐 SSH 접속",
        "NAS: " + host,
        "사용자: " + user,
        "출발지: " + source,
        "시각: " + when.strftime("%Y-%m-%d %H:%M:%S"),
    ])


def format_start_message(host, reason, when):
    """감시 시작 알림 본문."""
    return "\n".join([
        "👀 SSH 감시 시작: " + reason,
        "NAS: " + host,
        "시각: " + when.strftime("%Y-%m-%d %H:%M:%S"),
    ])


def start_reason(install, saved_boot_id, boot_id):
    """감시 시작 알림의 이유. 다시 시작은 무언가 고장 났다는 신호다."""
    if install:
        return REASON_INSTALL
    if saved_boot_id != boot_id:
        return REASON_BOOT
    return REASON_RESTART


def next_state(install, saved, boot_id, seed_cursor):
    """시작할 때 저장할 상태 {"boot_id", "cursor"}.

    - 처음 설치(--install, 저장된 상태 없음): 지금 journal 끝을 cursor 로 삼아 지난 접속을 보내지 않는다.
    - 부팅이 바뀜: journal 은 메모리에만 있어 지난 부팅의 cursor 는 쓸 수 없다. cursor 를 비운다.
    - 그 밖에는 그대로 둔다.
    """
    if install and saved is None:
        return {"boot_id": boot_id, "cursor": seed_cursor()}
    if saved is None or saved.get("boot_id") != boot_id:
        return {"boot_id": boot_id, "cursor": None}
    return saved


def journal_args(cursor):
    """sshd 줄을 따라 읽는 journalctl 명령. cursor 가 없으면 이번 부팅의 처음부터 읽는다."""
    if cursor:
        position = ["--after-cursor=" + cursor]
    else:
        # -f 는 기본으로 마지막 10줄부터 보여 주므로 --no-tail 이 있어야 처음부터 읽는다.
        position = ["-b", "--no-tail"]
    return [JOURNALCTL, "-f", "-o", "json"] + position + ["_COMM=sshd"]


def parse_entry(raw):
    """journal JSON 줄 하나(bytes 또는 str)를 dict 로 푼다. 풀 수 없으면 None."""
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8", errors="replace")
    # Windows PowerShell 5.1 은 파이프로 넘길 때 맨 앞에 BOM 을 붙인다.
    raw = raw.lstrip("﻿").strip()
    if not raw:
        return None
    try:
        entry = json.loads(raw)
    except ValueError:
        return None
    return entry if isinstance(entry, dict) else None


def access_message(entry, host, tz=None):
    """SSH 접속 줄이면 (접속 정보, 접속 알림 본문)을, 아니면 None 을 돌려준다."""
    access = parse_access(message_text(entry))
    if access is None or "__REALTIME_TIMESTAMP" not in entry:
        return None
    when = access_time(entry, tz)
    access["when"] = when
    return access, format_access_message(host, access["user"], access["source"], when)


def preview(lines, out, host, tz=None):
    """줄마다 SSH 접속이면 접속 알림 본문을 찍는다. 보내지 않고 아무것도 저장하지 않는다."""
    for raw in lines:
        entry = parse_entry(raw)
        if entry is None:
            continue
        result = access_message(entry, host, tz)
        if result is not None:
            out.write(result[1] + "\n\n")


# ---------------------------------------------------------------- 설정·로그

def parse_webhook_url(text):
    """env 파일 내용에서 DISCORD_WEBHOOK_URL 값을 찾는다. 메모장이 붙인 BOM·CRLF·따옴표를 견딘다."""
    for line in text.lstrip("﻿").splitlines():
        match = WEBHOOK_RE.match(line.strip("\r"))
        if match:
            return match.group(1)
    return None


def read_webhook_url(path=ENV_PATH):
    try:
        with open(path, encoding="utf-8-sig") as f:
            return parse_webhook_url(f.read())
    except OSError:
        return None


def format_log_line(now, result, fields):
    """`시각 결과 항목=값...` 한 줄. 값의 줄바꿈은 공백으로 바꾼다."""
    parts = [now.strftime("%Y-%m-%d %H:%M:%S"), result]
    for key, value in fields:
        parts.append("%s=%s" % (key, str(value).replace("\r", " ").replace("\n", " ")))
    return " ".join(parts)


def write_log(result, *fields):
    """월별 로그에 한 줄을 남긴다. 로그를 못 써도 감시는 계속한다. 웹훅 URL 은 넘기지 않는다."""
    now = datetime.datetime.now()
    path = os.path.join(LOG_DIR, "ssh-notify-%s.log" % now.strftime("%Y%m"))
    try:
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(path, "a", encoding="utf-8") as f:
            f.write(format_log_line(now, result, fields) + "\n")
        os.chmod(path, 0o644)
    except OSError:
        pass


# ---------------------------------------------------------------- 전송

def webhook_target(url):
    return url + ("&" if "?" in url else "?") + "wait=true"


def post_webhook(url, content):
    """웹훅으로 한 번 보낸다. 실패하면 예외를 던진다 (HTTPError 는 code·headers 를 가진다)."""
    body = json.dumps({
        "username": "ssh-notify",
        "content": content,
        "allowed_mentions": {"parse": []},
    }, ensure_ascii=False).encode("utf-8")
    request = urllib.request.Request(webhook_target(url), data=body, method="POST", headers={
        "Content-Type": "application/json; charset=utf-8",
        # 넣지 않으면 기본값 Python-urllib 이 가고 디스코드가 403 을 돌려준다.
        "User-Agent": USER_AGENT,
    })
    with urllib.request.urlopen(request, timeout=ATTEMPT_TIMEOUT_SECONDS) as response:
        response.read()


def retry_delay(error):
    """429 면 Retry-After 초만큼(최대 60초), 그 밖의 실패는 5초."""
    if getattr(error, "code", None) == 429:
        headers = getattr(error, "headers", None)
        value = headers.get("Retry-After") if headers is not None else None
        try:
            seconds = float(value)
        except (TypeError, ValueError):
            return DEFAULT_RETRY_SECONDS
        return int(min(max(math.ceil(seconds), 0), MAX_RETRY_SECONDS))
    return DEFAULT_RETRY_SECONDS


def send_with_retry(send_once, content, sleep=time.sleep):
    """최대 3번 시도한다. (성공 여부, 시도 횟수, 마지막 오류) 를 돌려준다."""
    last_error = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            send_once(content)
            return True, attempt, ""
        except Exception as error:  # 어떤 실패든 다시 시도하고, 끝내 실패하면 기록하고 넘어간다.
            last_error = str(error) or type(error).__name__
            if attempt < MAX_ATTEMPTS:
                sleep(retry_delay(error))
    return False, MAX_ATTEMPTS, last_error


# ---------------------------------------------------------------- 상태·잠금

def read_boot_id():
    with open(BOOT_ID_PATH) as f:
        return f.read().strip()


def load_state():
    try:
        with open(STATE_PATH, encoding="utf-8") as f:
            state = json.load(f)
    except (OSError, ValueError):
        return None
    return state if isinstance(state, dict) else None


def save_state(state):
    """임시 파일에 쓰고 바꿔 끼운다. 중간에 죽어도 cursor.json 이 반쯤 쓰인 채로 남지 않는다."""
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_PATH)


def seed_cursor():
    """지금 journal 의 마지막 sshd 줄의 cursor. 없으면 None."""
    try:
        output = subprocess.run([JOURNALCTL, "-o", "json", "-n", "1", "_COMM=sshd"],
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                timeout=30, check=False).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    for raw in reversed(output.splitlines()):
        entry = parse_entry(raw)
        if entry and entry.get("__CURSOR"):
            return entry["__CURSOR"]
    return None


def try_lock():
    """state/lock 을 잡는다. 잡으면 파일 객체를, 다른 프로세스가 잡고 있으면 None 을 돌려준다."""
    import fcntl  # Windows 에 없으므로 여기서만 부른다. PC 시험이 모듈을 불러올 수 있게 하려는 것이다.

    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    handle = open(LOCK_PATH, "a")
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        handle.close()
        return None
    return handle


def is_detector(pid):
    """그 PID 가 감지 장치인지 /proc 의 명령 줄로 확인한다. 낡은 pid 파일로 엉뚱한 프로세스를 죽이지 않게 한다."""
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            cmdline = f.read()
    except OSError:
        return False
    return b"ssh-notify.py" in cmdline and b"--run" in cmdline


def stop_detector():
    """돌고 있는 감지 장치에 SIGTERM 을 보내고 잠금이 풀릴 때까지 최대 10초 기다린다."""
    handle = try_lock()
    if handle is not None:
        handle.close()
        print("감지 장치가 돌고 있지 않다.")
        return 0
    try:
        with open(PID_PATH) as f:
            pid = int(f.read().strip())
    except (OSError, ValueError):
        pid = None
    if pid is None or not is_detector(pid):
        print("감지 장치의 PID 를 찾지 못했다 (%s)." % PID_PATH)
        return 1
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + STOP_WAIT_SECONDS
    while time.monotonic() < deadline:
        handle = try_lock()
        if handle is not None:
            handle.close()
            print("감지 장치를 멈췄다 (PID %d)." % pid)
            return 0
        time.sleep(0.2)
    print("%d초 안에 멈추지 않았다 (PID %d)." % (STOP_WAIT_SECONDS, pid))
    return 1


# ---------------------------------------------------------------- 감지 장치 본체

class Detector(object):
    def __init__(self, url, reason, state, host):
        self.url = url
        self.reason = reason
        self.state = state
        self.host = host
        self.start_alert_sent = False
        self.journal = None

    def send(self, content):
        return send_with_retry(lambda text: post_webhook(self.url, text), content)

    def log_send(self, ok, attempts, error, kind_fields):
        if ok:
            write_log("sent", *(kind_fields + [("attempts", attempts)]))
        else:
            # 오류 문구에 웹훅 URL 이 섞이지 않게 지운다.
            write_log("failed", *(kind_fields + [("attempts", attempts),
                                                  ("error", error.replace(self.url, "<webhook>"))]))

    def send_start_alert(self):
        content = format_start_message(self.host, self.reason, datetime.datetime.now())
        ok, attempts, error = self.send(content)
        self.log_send(ok, attempts, error, [("kind", "start"), ("reason", REASON_LOG[self.reason])])
        self.start_alert_sent = True

    def handle_line(self, raw):
        entry = parse_entry(raw)
        if entry is None:
            return
        result = access_message(entry, self.host)
        if result is not None:
            access, content = result
            ok, attempts, error = self.send(content)
            self.log_send(ok, attempts, error, [
                ("kind", "access"), ("user", access["user"]), ("src", access["source"]),
                ("at", access["when"].strftime("%Y-%m-%dT%H:%M:%S")),
            ])
        cursor = entry.get("__CURSOR")
        if cursor:
            # 보낸 뒤에 저장한다. 같은 알림이 두 번 갈 수는 있어도 빠지지는 않는다.
            self.state = {"boot_id": self.state["boot_id"], "cursor": cursor}
            save_state(self.state)

    def run_journal_once(self):
        """journalctl 을 한 번 띄워 끝날 때까지 읽는다. 종료 코드를 돌려준다."""
        self.journal = subprocess.Popen(journal_args(self.state.get("cursor")),
                                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        time.sleep(STARTUP_CHECK_SECONDS)
        if self.journal.poll() is None:
            # 처음 읽기 시작했을 때만 감시 시작 알림을 보낸다. 그래서 늦은 접속 알림은 이 알림 뒤에 간다.
            if not self.start_alert_sent:
                self.send_start_alert()
            for raw in iter(self.journal.stdout.readline, b""):
                self.handle_line(raw)
        self.journal.stdout.close()
        return self.journal.wait()

    def run(self):
        wait = RESTART_WAIT_MIN_SECONDS
        while True:
            started = time.monotonic()
            code = self.run_journal_once()
            if time.monotonic() - started > HEALTHY_RUN_SECONDS:
                wait = RESTART_WAIT_MIN_SECONDS
            write_log("journal-exit", ("code", code), ("wait", wait))
            time.sleep(wait)
            wait = min(wait * 2, RESTART_WAIT_MAX_SECONDS)

    def stop(self, signum, frame):
        if self.journal is not None and self.journal.poll() is None:
            self.journal.terminate()
        raise SystemExit(0)


def run_detector(install):
    """백그라운드 쪽. 잠금을 잡고, 시작 이유와 읽기 위치를 정한 뒤 journal 을 계속 읽는다."""
    lock = try_lock()
    if lock is None:
        return 0  # 이미 돌고 있다. 매시간 작업이 매번 여기서 끝나므로 로그를 남기지 않는다.
    with open(PID_PATH, "w") as f:
        f.write(str(os.getpid()))
    url = read_webhook_url()
    if not url:
        write_log("error", ("reason", "no-webhook-url"))
        return 1
    try:
        boot_id = read_boot_id()
    except OSError:
        write_log("error", ("reason", "no-boot-id"))
        return 1
    saved = load_state()
    reason = start_reason(install, saved.get("boot_id") if saved else None, boot_id)
    state = next_state(install, saved, boot_id, seed_cursor)
    if state != saved:
        save_state(state)
    detector = Detector(url, reason, state, socket.gethostname())
    signal.signal(signal.SIGTERM, detector.stop)
    try:
        detector.run()
    except Exception as error:  # 예상 못 한 고장도 로그에 남긴다. 매시간 작업이 '다시 시작'으로 띄운다.
        write_log("error", ("reason", "crash"), ("error", "%s: %s" % (type(error).__name__, error)))
        return 1
    return 0


def spawn_background(install):
    """자기 자신을 --run 으로 따로 띄우고 바로 끝난다. DSM 작업과 install.sh 가 기다리지 않게 한다."""
    args = [sys.executable, os.path.abspath(__file__), "--run"] + (["--install"] if install else [])
    subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True, cwd="/")


def main(argv=None):
    parser = argparse.ArgumentParser(description="시놀로지 SSH 접속을 디스코드 웹훅으로 알린다.")
    parser.add_argument("--install", action="store_true", help="시작 이유를 '설치'로 한다 (install.sh 가 쓴다)")
    parser.add_argument("--stop", action="store_true", help="돌고 있는 감지 장치를 멈춘다 (root)")
    parser.add_argument("--preview", action="store_true",
                        help="stdin 의 journal JSON 줄로 보낼 메시지를 화면에만 찍는다")
    parser.add_argument("--run", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.preview + args.stop + args.install > 1:
        parser.error("--install, --stop, --preview 는 하나만 쓴다")
    if args.preview:
        # Windows 에서 출력을 파일로 돌리면 cp949 가 되어 이모지에서 죽는다.
        sys.stdout.reconfigure(encoding="utf-8")
        preview(sys.stdin.buffer, sys.stdout, socket.gethostname())
        return 0
    if args.stop:
        try:
            return stop_detector()
        except PermissionError:
            print("root 로 실행한다: sudo python3 %s --stop" % os.path.abspath(__file__))
            return 1
    if args.run:
        return run_detector(args.install)
    spawn_background(args.install)
    return 0


if __name__ == "__main__":
    sys.exit(main())
