#!/usr/bin/env python3
"""ssh-notify: 시놀로지 NAS 의 SSH 접속을 journal 에서 알아채 디스코드 웹훅으로 알린다.

용어는 synology/CONTEXT.md 를 따른다. NAS 의 python3 가 3.8.12 이므로 3.8 문법만 쓴다.

    python3 ssh-notify.py --preview < 줄파일   # journal JSON 줄로 보낼 메시지를 화면에만 찍는다
"""
import argparse
import datetime
import json
import re
import socket
import sys

REASON_INSTALL = "설치"
REASON_BOOT = "부팅"
REASON_RESTART = "다시 시작"

JOURNALCTL = "/usr/bin/journalctl"

# 줄 맨 앞에서만 맞춘다. 실패 줄의 사용자 이름 자리에 이 문구를 넣어도 SSH 접속으로 보지 않는다.
ACCEPTED_RE = re.compile(r"^Accepted (\S+) for (\S+) from (\S+) port (\d+)")


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
    raw = raw.strip()
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


def main(argv=None):
    parser = argparse.ArgumentParser(description="시놀로지 SSH 접속을 디스코드 웹훅으로 알린다.")
    parser.add_argument("--preview", action="store_true",
                        help="stdin 의 journal JSON 줄로 보낼 메시지를 화면에만 찍는다")
    args = parser.parse_args(argv)
    if args.preview:
        # Windows 에서 출력을 파일로 돌리면 cp949 가 되어 이모지에서 죽는다.
        sys.stdout.reconfigure(encoding="utf-8")
        preview(sys.stdin.buffer, sys.stdout, socket.gethostname())
        return 0
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
