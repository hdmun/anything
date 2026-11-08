"""ssh-notify.py 시험. synology/ 안에서 `python -m unittest` 로 돌린다.

실제 journalctl·flock·디스코드는 다루지 않는다. README 의 '실제 시험'에서 확인한다.
"""
import datetime
import email.message
import importlib.util
import io
import json
import os
import unittest
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURE = os.path.join(HERE, "testdata", "sshd-journal.jsonl")

# 파일 이름에 '-' 가 있어 import 문으로는 불러올 수 없다.
_spec = importlib.util.spec_from_file_location("ssh_notify", os.path.join(HERE, "ssh-notify.py"))
sn = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sn)

KST = datetime.timezone(datetime.timedelta(hours=9))


def load_fixture():
    with open(FIXTURE, "rb") as f:
        return [json.loads(line) for line in f if line.strip()]


class AccessDecisionTest(unittest.TestCase):
    def test_accepted_methods_are_access(self):
        cases = [
            ("Accepted publickey for user1 from 203.0.113.10 port 52719 ssh2: ED25519 SHA256:x",
             "user1", "203.0.113.10"),
            ("Accepted password for user1 from 203.0.113.10 port 59030 ssh2", "user1", "203.0.113.10"),
            ("Accepted keyboard-interactive/pam for user2 from 203.0.113.11 port 40022 ssh2",
             "user2", "203.0.113.11"),
        ]
        for message, user, source in cases:
            with self.subTest(message=message):
                self.assertEqual(sn.parse_access(message), {"user": user, "source": source})

    def test_other_sshd_lines_are_not_access(self):
        for message in [
            "Failed password for user1 from 198.51.100.7 port 41000 ssh2",
            "Invalid user admin from 198.51.100.7 port 41001",
            "Disconnected from user user1 203.0.113.10 port 52719",
            "subsystem request for sftp by user user1 failed, subsystem not found",
            "pam_unix(sshd:session): session opened for user user1 by (uid=0)",
            "",
        ]:
            with self.subTest(message=message):
                self.assertIsNone(sn.parse_access(message))

    def test_accepted_text_inside_failed_line_is_not_access(self):
        message = ("Failed password for invalid user Accepted publickey for x from 198.51.100.1 port 1"
                   " from 198.51.100.7 port 41002 ssh2")
        self.assertIsNone(sn.parse_access(message))

    def test_ipv6_source(self):
        access = sn.parse_access("Accepted publickey for user2 from 2001:db8::10 port 40022 ssh2")
        self.assertEqual(access["source"], "2001:db8::10")

    def test_message_as_byte_array(self):
        entry = {"MESSAGE": list("Accepted password for user3 from 198.51.100.20 port 1 ssh2".encode())}
        self.assertEqual(sn.message_text(entry),
                         "Accepted password for user3 from 198.51.100.20 port 1 ssh2")

    def test_message_byte_array_with_invalid_utf8(self):
        entry = {"MESSAGE": [65, 0xff, 66]}
        self.assertEqual(sn.message_text(entry), "A�B")

    def test_fixture_access_lines(self):
        users = [sn.parse_access(sn.message_text(e)) for e in load_fixture()]
        found = [(a["user"], a["source"]) for a in users if a]
        self.assertEqual(found, [
            ("user1", "203.0.113.10"),
            ("user1", "203.0.113.10"),
            ("user2", "2001:db8::10"),
            ("user3", "198.51.100.20"),
        ])


class AccessMessageTest(unittest.TestCase):
    def test_format(self):
        when = datetime.datetime(2026, 11, 8, 9, 12, 29)
        self.assertEqual(
            sn.format_access_message("nas", "user1", "203.0.113.10", when),
            "🔐 SSH 접속\nNAS: nas\n사용자: user1\n출발지: 203.0.113.10\n시각: 2026-11-08 09:12:29",
        )

    def test_time_is_journal_time_in_given_zone(self):
        entry = {"__REALTIME_TIMESTAMP": "1794036293123456"}
        self.assertEqual(sn.access_time(entry, KST).strftime("%Y-%m-%d %H:%M:%S"), "2026-11-07 16:24:53")

    def test_access_message_from_entry(self):
        entry = load_fixture()[0]
        access, text = sn.access_message(entry, "nas", KST)
        self.assertEqual(access["user"], "user1")
        self.assertEqual(text.splitlines()[-1], "시각: 2026-11-07 16:24:53")

    def test_non_access_entry_gives_none(self):
        self.assertIsNone(sn.access_message(load_fixture()[3], "nas", KST))


class StartAlertTest(unittest.TestCase):
    def test_reason(self):
        self.assertEqual(sn.start_reason(True, "b1", "b1"), "설치")
        self.assertEqual(sn.start_reason(True, None, "b1"), "설치")
        self.assertEqual(sn.start_reason(False, None, "b1"), "부팅")
        self.assertEqual(sn.start_reason(False, "b0", "b1"), "부팅")
        self.assertEqual(sn.start_reason(False, "b1", "b1"), "다시 시작")

    def test_format(self):
        when = datetime.datetime(2026, 11, 8, 9, 0, 5)
        self.assertEqual(
            sn.format_start_message("nas", "부팅", when),
            "👀 SSH 감시 시작: 부팅\nNAS: nas\n시각: 2026-11-08 09:00:05",
        )


class StateTest(unittest.TestCase):
    def never(self):
        raise AssertionError("seed_cursor 를 부르면 안 된다")

    def test_first_install_seeds_cursor(self):
        state = sn.next_state(True, None, "b1", lambda: "c-now")
        self.assertEqual(state, {"boot_id": "b1", "cursor": "c-now"})

    def test_reinstall_keeps_cursor(self):
        saved = {"boot_id": "b1", "cursor": "c1"}
        self.assertEqual(sn.next_state(True, saved, "b1", self.never), saved)

    def test_new_boot_clears_cursor(self):
        saved = {"boot_id": "b0", "cursor": "c0"}
        self.assertEqual(sn.next_state(False, saved, "b1", self.never), {"boot_id": "b1", "cursor": None})
        self.assertEqual(sn.next_state(True, saved, "b1", self.never), {"boot_id": "b1", "cursor": None})

    def test_restart_keeps_cursor(self):
        saved = {"boot_id": "b1", "cursor": "c1"}
        self.assertEqual(sn.next_state(False, saved, "b1", self.never), saved)


class JournalArgsTest(unittest.TestCase):
    def test_with_cursor(self):
        args = sn.journal_args("s=1;i=2")
        self.assertIn("--after-cursor=s=1;i=2", args)
        self.assertNotIn("-b", args)
        self.assertEqual(args[0], "/usr/bin/journalctl")
        self.assertEqual(args[-1], "_COMM=sshd")
        self.assertIn("-f", args)

    def test_without_cursor_reads_whole_boot(self):
        args = sn.journal_args(None)
        self.assertIn("-b", args)
        self.assertIn("--no-tail", args)
        self.assertFalse(any(a.startswith("--after-cursor") for a in args))


class PreviewTest(unittest.TestCase):
    def test_prints_only_access_alerts(self):
        out = io.StringIO()
        with open(FIXTURE, "rb") as f:
            sn.preview(f, out, "nas", KST)
        blocks = out.getvalue().strip().split("\n\n")
        self.assertEqual(len(blocks), 4)
        self.assertTrue(all(b.startswith("🔐 SSH 접속\nNAS: nas\n") for b in blocks))
        self.assertIn("출발지: 2001:db8::10", blocks[2])
        self.assertIn("사용자: user3", blocks[3])

    def test_skips_broken_lines(self):
        out = io.StringIO()
        sn.preview([b"", b"not json", b"[1, 2]"], out, "nas", KST)
        self.assertEqual(out.getvalue(), "")


class FakeHTTPError(Exception):
    def __init__(self, code, headers=None):
        super(FakeHTTPError, self).__init__("HTTP Error %d" % code)
        self.code = code
        self.headers = headers or {}


class RetryTest(unittest.TestCase):
    def run_sends(self, errors):
        """errors 의 항목을 차례로 던지고(None 이면 성공) 결과와 기다린 시간들을 돌려준다."""
        queue = list(errors)
        sleeps = []

        def send_once(content):
            error = queue.pop(0) if queue else None
            if error is not None:
                raise error

        result = sn.send_with_retry(send_once, "본문", sleep=sleeps.append)
        return result, sleeps

    def test_first_try_succeeds(self):
        self.assertEqual(self.run_sends([None]), ((True, 1, ""), []))

    def test_429_waits_retry_after(self):
        result, sleeps = self.run_sends([FakeHTTPError(429, {"Retry-After": "2.5"}), None])
        self.assertEqual(result, (True, 2, ""))
        self.assertEqual(sleeps, [3])

    def test_429_retry_after_is_capped_at_60(self):
        _, sleeps = self.run_sends([FakeHTTPError(429, {"Retry-After": "120"}), None])
        self.assertEqual(sleeps, [60])

    def test_429_without_header_waits_default(self):
        _, sleeps = self.run_sends([FakeHTTPError(429), None])
        self.assertEqual(sleeps, [5])

    def test_three_failures_give_up(self):
        result, sleeps = self.run_sends([FakeHTTPError(500), OSError("timed out"), FakeHTTPError(404)])
        self.assertEqual(result, (False, 3, "HTTP Error 404"))
        self.assertEqual(sleeps, [5, 5])

    def test_real_http_error_object(self):
        headers = email.message.Message()
        headers["Retry-After"] = "7"
        error = urllib.error.HTTPError("https://example.invalid", 429, "Too Many Requests", headers, None)
        self.assertEqual(sn.retry_delay(error), 7)

    def test_webhook_target(self):
        self.assertEqual(sn.webhook_target("https://x/api/webhooks/1/t"), "https://x/api/webhooks/1/t?wait=true")
        self.assertEqual(sn.webhook_target("https://x/a?thread_id=1"), "https://x/a?thread_id=1&wait=true")


class EnvAndLogTest(unittest.TestCase):
    URL = "https://discord.com/api/webhooks/1/token"

    def test_webhook_url_survives_notepad(self):
        text = "﻿# 견본\r\nDISCORD_WEBHOOK_URL=\"%s\"\r\n" % self.URL
        self.assertEqual(sn.parse_webhook_url(text), self.URL)

    def test_webhook_url_missing_or_not_https(self):
        self.assertIsNone(sn.parse_webhook_url("# 비어 있음\n"))
        self.assertIsNone(sn.parse_webhook_url("DISCORD_WEBHOOK_URL=http://x\n"))
        self.assertIsNone(sn.parse_webhook_url("DISCORD_WEBHOOK_URL=\n"))

    def test_log_line(self):
        now = datetime.datetime(2026, 11, 8, 9, 12, 30)
        line = sn.format_log_line(now, "sent", [("kind", "access"), ("user", "user1"), ("attempts", 1)])
        self.assertEqual(line, "2026-11-08 09:12:30 sent kind=access user=user1 attempts=1")

    def test_log_line_has_no_newline(self):
        now = datetime.datetime(2026, 11, 8, 9, 12, 30)
        line = sn.format_log_line(now, "failed", [("error", "a\r\nb")])
        self.assertNotIn("\n", line)


class DetectorLineTest(unittest.TestCase):
    """줄 하나 처리: 보낸 뒤에 cursor 를 저장하고, 실패해도 저장하고 넘어간다."""

    def setUp(self):
        self.events = []
        self._saved = (sn.save_state, sn.write_log, sn.access_time)
        sn.save_state = lambda state: self.events.append(("save", state["cursor"]))
        sn.write_log = lambda result, *fields: self.events.append(("log", result, dict(fields)))
        real_access_time = self._saved[2]
        sn.access_time = lambda entry, tz=None: real_access_time(entry, KST)

    def tearDown(self):
        sn.save_state, sn.write_log, sn.access_time = self._saved

    def detector(self, ok):
        detector = sn.Detector("https://discord.com/api/webhooks/1/token", "부팅",
                               {"boot_id": "b1", "cursor": None}, "nas")

        def send(content):
            self.events.append(("send", content.splitlines()[0]))
            return (True, 1, "") if ok else (False, 3, "HTTP Error 404 https://discord.com/api/webhooks/1/token")

        detector.send = send
        return detector

    def test_access_line_sends_then_saves(self):
        entry = load_fixture()[0]
        self.detector(True).handle_line(json.dumps(entry).encode())
        kinds = [e[0] for e in self.events]
        self.assertEqual(kinds, ["send", "log", "save"])
        self.assertEqual(self.events[1][1], "sent")
        self.assertEqual(self.events[1][2]["at"], "2026-11-07T16:24:53")
        self.assertEqual(self.events[2][1], entry["__CURSOR"])

    def test_failed_send_is_logged_without_url_and_cursor_still_saved(self):
        entry = load_fixture()[0]
        self.detector(False).handle_line(json.dumps(entry).encode())
        self.assertEqual([e[0] for e in self.events], ["send", "log", "save"])
        self.assertEqual(self.events[1][1], "failed")
        self.assertNotIn("discord.com", self.events[1][2]["error"])

    def test_other_line_only_saves_cursor(self):
        entry = load_fixture()[3]
        self.detector(True).handle_line(json.dumps(entry).encode())
        self.assertEqual(self.events, [("save", entry["__CURSOR"])])


if __name__ == "__main__":
    unittest.main()
