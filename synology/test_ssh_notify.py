"""ssh-notify.py 시험. synology/ 안에서 `python -m unittest` 로 돌린다.

실제 journalctl·flock·디스코드는 다루지 않는다. README 의 '실제 시험'에서 확인한다.
"""
import datetime
import importlib.util
import io
import json
import os
import unittest

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


if __name__ == "__main__":
    unittest.main()
