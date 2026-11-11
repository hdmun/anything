# -*- coding: utf-8 -*-
import json
import pathlib
import re
import shutil
import tempfile
import unittest

from helpers import PLUGIN_ROOT
from relaylib import leak


class TestEdgeCasesWithGitleaks(unittest.TestCase):
    """엣지 케이스 표 1~13 을 실제 gitleaks 로 확인하는 테스트."""

    @classmethod
    def setUpClass(cls):
        if not shutil.which("gitleaks"):
            raise unittest.SkipTest("gitleaks 가 PATH 에 없다")
        cls.default_text = leak.DEFAULT_CONFIG.read_text(encoding="utf-8")
        # 빈 사용자 규칙
        cls.user_text = 'title = "empty"\n'
        cls.cfg_text = leak.build_config(cls.default_text, cls.user_text, None)
        cls._tmp = tempfile.NamedTemporaryFile("w", delete=False, suffix=".toml", encoding="utf-8")
        cls._tmp.write(cls.cfg_text)
        cls._tmp.close()
        cls.cfg_path = pathlib.Path(cls._tmp.name)

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "cfg_path") and cls.cfg_path.exists():
            cls.cfg_path.unlink(missing_ok=True)

    def scan(self, text):
        import subprocess

        def run(argv, stdin=None):
            r = subprocess.run(argv, input=stdin, capture_output=True, text=True, encoding="utf-8")
            return r.returncode, r.stdout

        return leak.scan_text(text, self.cfg_path, run)

    def test_case_01_rfc5737(self):
        # 1. RFC 5737 주소 안 걸림
        for ip in ("192.0.2.10", "198.51.100.7", "203.0.113.200"):
            self.assertEqual(self.scan(ip), [], ip)

    def test_case_02_loopback_and_zero(self):
        # 2. 127.0.0.1, 0.0.0.0 안 걸림
        for ip in ("127.0.0.1", "0.0.0.0"):
            self.assertEqual(self.scan(ip), [], ip)

    def test_case_03_private_ip(self):
        # 3. 사설 IP (10/8, 172.16/12, 192.168/16) 걸림
        ips = [
            ".".join(["10", "0", "0", "1"]),
            ".".join(["172", "16", "0", "1"]),
            ".".join(["192", "168", "1", "1"]),
        ]
        for ip in ips:
            res = self.scan(ip)
            self.assertTrue(res, f"should catch {ip}")
            self.assertEqual(res[0]["rule"], "relay-ipv4")

    def test_case_04_public_ip(self):
        # 4. 공인 IP 걸림
        ip = ".".join(["8", "8", "8", "8"])
        res = self.scan(ip)
        self.assertTrue(res)
        self.assertEqual(res[0]["rule"], "relay-ipv4")

    def test_case_05_sentence_ending_dot_ip(self):
        # 5. 문장 끝 마침표가 붙은 사설 IP 걸림
        text = "이 주소는 " + ".".join(["10", "0", "0", "1"]) + ". 다음 문장"
        res = self.scan(text)
        self.assertTrue(res)
        self.assertEqual(res[0]["rule"], "relay-ipv4")

    def test_case_06_octet_over_255(self):
        # 6. 옥텟 하나가 255 를 넘는 네 마디 안 걸림
        self.assertEqual(self.scan("300.1.1.1"), [])

    def test_case_07_three_parts_version(self):
        # 7. 세 마디 버전 안 걸림
        self.assertEqual(self.scan("1.2.3"), [])

    def test_case_08_five_parts_version(self):
        # 8. 다섯 마디 버전 안 걸림
        self.assertEqual(self.scan("1.2.3.4.5"), [])

    def test_case_09_four_parts_version_caught_as_ipv4(self):
        # 9. 옥텟 범위 안의 네 마디 버전 문자열 (오탐)
        v = ".".join(["1", "2", "3", "4"])
        res = self.scan(v)
        self.assertTrue(res)
        self.assertEqual(res[0]["rule"], "relay-ipv4")

    def test_case_10_discord_webhook(self):
        # 10. 디스코드 웹훅 URL (discord.com, discordapp.com)
        urls = [
            "https://" + "discord.com/api/webhooks/" + "12345678901234567/token-abc",
            "https://" + "discordapp.com/api/webhooks/" + "12345678901234567890/token-abc",
        ]
        for u in urls:
            res = self.scan(u)
            self.assertTrue(res, f"should catch {u}")
            self.assertEqual(res[0]["rule"], "relay-discord-webhook")

    def test_case_11_discord_dummy(self):
        # 11. 테스트 더미 안 걸림
        self.assertEqual(self.scan("discord.com/api/webhooks/1/token"), [])

    def test_case_12_windows_pc_name(self):
        # 12. DESKTOP- + 영문 대문자·숫자 7자 걸림
        name = "-".join(["DESKTOP", "ABC1234"])
        res = self.scan(name)
        self.assertTrue(res)
        self.assertEqual(res[0]["rule"], "relay-windows-pc-name")

    def test_case_13_windows_pc_name_non_7_chars(self):
        # 13. DESKTOP- + 6자 또는 8자 안 걸림
        self.assertEqual(self.scan("-".join(["DESKTOP", "ABC123"])), [])
        self.assertEqual(self.scan("-".join(["DESKTOP", "ABC12345"])), [])


class TestBuildConfig(unittest.TestCase):
    def setUp(self):
        self.default_text = leak.DEFAULT_CONFIG.read_text(encoding="utf-8")

    def test_valid_combination(self):
        user = 'title = "t"\n[[rules]]\nid = "user-1"\nregex = "foo"\n'
        repo = '[[allowlists]]\nregexes = ["bar"]\n'
        combined = leak.build_config(self.default_text, user, repo)
        self.assertIn("user-1", combined)
        self.assertIn("foo", combined)
        self.assertIn("bar", combined)
        self.assertNotIn('title = "t"', combined)

    def test_user_disallowed_key_raises(self):
        user = '[extend]\nuseDefault = true\n'
        with self.assertRaises(leak.LeakError) as ctx:
            leak.build_config(self.default_text, user, None)
        self.assertIn("허용되지 않은", str(ctx.exception))

    def test_repo_disallowed_key_raises(self):
        repo = '[[rules]]\nid = "r"\n'
        with self.assertRaises(leak.LeakError) as ctx:
            leak.build_config(self.default_text, None, repo)
        self.assertIn("허용되지 않은", str(ctx.exception))

    def test_syntax_error_raises(self):
        with self.assertRaises(leak.LeakError):
            leak.build_config(self.default_text, "invalid [[ toml", None)

    @unittest.skipUnless(shutil.which("gitleaks"), "gitleaks 가 PATH 에 없다")
    def test_repo_allowlist_unblocks_ip(self):
        # 저장소 허용 목록이 RFC 5737 밖 주소 하나를 허용 -> 그 주소는 안 걸리고 다른 주소는 걸린다
        allowed_ip = ".".join(["10", "99", "88", "77"])
        blocked_ip = ".".join(["10", "1", "2", "3"])
        escaped = re.escape(allowed_ip)
        repo = f"[[allowlists]]\nregexes = ['''^{escaped}$''']\n"
        cfg_text = leak.build_config(self.default_text, 'title = "t"\n', repo)
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".toml", encoding="utf-8") as tmp:
            tmp.write(cfg_text)
            tmp_path = pathlib.Path(tmp.name)
        try:
            import subprocess

            def run(argv, stdin=None):
                r = subprocess.run(argv, input=stdin, capture_output=True, text=True, encoding="utf-8")
                return r.returncode, r.stdout

            self.assertEqual(leak.scan_text(allowed_ip, tmp_path, run), [])
            self.assertTrue(leak.scan_text(blocked_ip, tmp_path, run))
        finally:
            tmp_path.unlink(missing_ok=True)


class TestChangedAllowlists(unittest.TestCase):
    def test_detects_changed_files(self):
        def fake_git(wt, *args):
            return ".gitleaksignore\nsrc/main.py\n"

        res = leak.changed_allowlists("/fake", "origin/main", fake_git)
        self.assertEqual(res, [".gitleaksignore"])

    def test_detects_repo_allow_changed(self):
        def fake_git(wt, *args):
            return ".ai/leak-allow.toml\n"

        res = leak.changed_allowlists("/fake", "origin/main", fake_git)
        self.assertEqual(res, [".ai/leak-allow.toml"])

    def test_empty_when_no_allowlist_changed(self):
        def fake_git(wt, *args):
            return "README.md\nsrc/app.py\n"

        res = leak.changed_allowlists("/fake", "origin/main", fake_git)
        self.assertEqual(res, [])


class TestWriteLog(unittest.TestCase):
    def test_creates_log_and_gitignore(self):
        with tempfile.TemporaryDirectory() as td:
            wt = pathlib.Path(td)
            findings = [{"rule": "relay-ipv4", "file": "src/a.py", "line": 10}]
            rel = leak.write_log(wt, "push", findings)
            self.assertTrue(rel.startswith(".ai/leak/"))
            self.assertTrue(rel.endswith("-push.json"))
            log_file = wt / rel
            self.assertTrue(log_file.is_file())
            gitignore = wt / ".ai/leak/.gitignore"
            self.assertTrue(gitignore.is_file())
            self.assertEqual(gitignore.read_text(encoding="utf-8").strip(), "*")
            data = json.loads(log_file.read_text(encoding="utf-8"))
            self.assertEqual(data["findings"], findings)


class TestScanRange(unittest.TestCase):
    def test_no_commits_returns_empty(self):
        def fake_git(wt, *args):
            return ""

        def fake_run(argv, stdin=None):
            return 0, ""

        res = leak.scan_range("/wt", "origin/main", "/cfg", fake_run, fake_git)
        self.assertEqual(res, [])

    def test_commit_message_findings_have_short_sha(self):
        c1 = "1234567890abcdef1234567890abcdef12345678"

        def fake_git(wt, *args):
            if args[1] == "--format=%H":
                return c1 + "\n"
            if args[2] == "--format=%B":
                return "commit with leak\n"
            return ""

        def fake_run(argv, stdin=None):
            if argv[1] == "git":
                return 0, "[]"
            if argv[1] == "stdin":
                return 99, json.dumps([{"RuleID": "relay-ipv4", "StartLine": 1}])
            return 0, ""

        res = leak.scan_range("/wt", "origin/main", "/cfg", fake_run, fake_git)
        self.assertEqual(len(res), 1)
        self.assertEqual(res[0]["rule"], "relay-ipv4")
        self.assertEqual(res[0]["file"], f"커밋 메시지 {c1[:7]}")


class TestPublishActions(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.wt = pathlib.Path(self._d.name)
        # 임시 user rules 파일
        self.user_rules = self.wt / "user-rules.toml"
        self.user_rules.write_text('title = "test"\n', encoding="utf-8")

    def tearDown(self):
        self._d.cleanup()

    # --- push ---
    def test_push_success(self):
        def fake_git(wt, *args):
            if "branch" in args:
                return "feat-1"
            if "diff" in args:
                return ""
            if "--format=%H" in args:
                return ""
            return ""

        def fake_run(argv, cwd=None, stdin=None):
            return 0, ""

        dec = leak.push(self.wt, run=fake_run, git=fake_git, user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "pushed")
        self.assertEqual(dec["branch"], "feat-1")
        self.assertEqual(dec["range"], "origin/main..HEAD")

    def test_push_stop_allowlist_changed(self):
        def fake_git(wt, *args):
            if "diff" in args:
                return ".gitleaksignore\n"
            return ""

        def fake_run(argv, cwd=None, stdin=None):
            return 0, ""

        dec = leak.push(self.wt, run=fake_run, git=fake_git, user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "stop")
        self.assertEqual(dec["reason"], "allowlist_changed")
        self.assertEqual(dec["files"], [".gitleaksignore"])

    def test_push_stop_leak(self):
        def fake_git(wt, *args):
            if "--format=%H" in args:
                return "abcd1234567\n"
            if "--format=%B" in args:
                return "msg\n"
            return ""

        def fake_run(argv, cwd=None, stdin=None):
            if argv[1] == "git":
                return 99, json.dumps([{"RuleID": "relay-ipv4", "File": "src/ip.py", "StartLine": 5}])
            return 0, "[]"

        dec = leak.push(self.wt, run=fake_run, git=fake_git, user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "stop")
        self.assertEqual(dec["reason"], "leak")
        self.assertEqual(len(dec["findings"]), 1)
        self.assertTrue(dec["log"].startswith(".ai/leak/"))

    def test_push_stop_push_failed(self):
        def fake_git(wt, *args):
            return ""

        def fake_run(argv, cwd=None, stdin=None):
            return (1, "", "remote: error: push protection declined\nfatal: failed to push")

        dec = leak.push(self.wt, run=fake_run, git=fake_git, user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "stop")
        self.assertEqual(dec["reason"], "push_failed")
        self.assertIn("failed to push", dec["detail"])

    # --- pr ---
    def test_pr_exists(self):
        calls = []

        def fake_git(wt, *args):
            return "feat-pr"

        def fake_run(argv, cwd=None, stdin=None):
            calls.append(argv)
            if argv[1:3] == ["pr", "list"]:
                return 0, json.dumps([{"url": "https://github.com/org/repo/pull/123"}])
            return 0, ""

        body_file = self.wt / "body.md"
        body_file.write_text("body", encoding="utf-8")

        dec = leak.pr(self.wt, title="Title", body_file=body_file, run=fake_run, git=fake_git,
                      user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "exists")
        self.assertEqual(dec["pr"], "https://github.com/org/repo/pull/123")
        # gh pr create 를 부르지 않는다
        created_calls = [c for c in calls if c[1:3] == ["pr", "create"]]
        self.assertEqual(created_calls, [])

    def test_pr_created(self):
        calls = []

        def fake_git(wt, *args):
            return "feat-pr"

        def fake_run(argv, cwd=None, stdin=None):
            calls.append(argv)
            if argv[1:3] == ["pr", "list"]:
                return 0, "[]"
            if argv[1] == "stdin":
                return 0, "[]"
            if argv[1:3] == ["pr", "create"]:
                return 0, "https://github.com/org/repo/pull/456\n"
            return 0, ""

        body_file = self.wt / "body.md"
        body_file.write_text("clean body", encoding="utf-8")

        dec = leak.pr(self.wt, title="Title", body_file=body_file, run=fake_run, git=fake_git,
                      user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "created")
        self.assertEqual(dec["pr"], "https://github.com/org/repo/pull/456")

    def test_pr_stop_leak(self):
        calls = []

        def fake_git(wt, *args):
            return "feat-pr"

        def fake_run(argv, cwd=None, stdin=None):
            calls.append(argv)
            if argv[1:3] == ["pr", "list"]:
                return 0, "[]"
            if argv[1] == "stdin":
                return 99, json.dumps([{"RuleID": "relay-ipv4", "StartLine": 2}])
            return 0, ""

        body_file = self.wt / "body.md"
        body_file.write_text("body with leak", encoding="utf-8")

        dec = leak.pr(self.wt, title="Title", body_file=body_file, run=fake_run, git=fake_git,
                      user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "stop")
        self.assertEqual(dec["reason"], "leak")
        self.assertEqual(dec["findings"][0]["file"], "pr")
        # gh pr create 를 부르지 않는다
        self.assertEqual([c for c in calls if c[1:3] == ["pr", "create"]], [])

    def test_pr_stop_gh_failed(self):
        def fake_git(wt, *args):
            return "feat-pr"

        def fake_run(argv, cwd=None, stdin=None):
            if argv[1:3] == ["pr", "list"]:
                return 0, "[]"
            if argv[1] == "stdin":
                return 0, "[]"
            return (1, "", "graphql error: base branch not found")

        body_file = self.wt / "body.md"
        body_file.write_text("clean body", encoding="utf-8")

        dec = leak.pr(self.wt, title="Title", body_file=body_file, run=fake_run, git=fake_git,
                      user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "stop")
        self.assertEqual(dec["reason"], "gh_failed")
        self.assertIn("graphql error", dec["detail"])

    # --- comment ---
    def test_comment_posted(self):
        def fake_run(argv, cwd=None, stdin=None):
            if argv[1] == "stdin":
                return 0, "[]"
            if argv[1:3] == ["issue", "comment"]:
                return 0, "https://github.com/org/repo/issues/1#issuecomment-999\n"
            return 0, ""

        body_file = self.wt / "comment.md"
        body_file.write_text("clean comment", encoding="utf-8")

        dec = leak.comment(self.wt, issue_url="https://github.com/org/repo/issues/1",
                           body_file=body_file, run=fake_run, git=lambda *a: "",
                           user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "posted")
        self.assertEqual(dec["url"], "https://github.com/org/repo/issues/1#issuecomment-999")

    def test_comment_stop_leak(self):
        calls = []

        def fake_run(argv, cwd=None, stdin=None):
            calls.append(argv)
            if argv[1] == "stdin":
                return 99, json.dumps([{"RuleID": "relay-ipv4", "StartLine": 1}])
            return 0, ""

        body_file = self.wt / "comment.md"
        body_file.write_text("leaking comment", encoding="utf-8")

        dec = leak.comment(self.wt, issue_url="https://github.com/org/repo/issues/1",
                           body_file=body_file, run=fake_run, git=lambda *a: "",
                           user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "stop")
        self.assertEqual(dec["reason"], "leak")
        self.assertEqual(dec["findings"][0]["file"], "comment")
        # gh issue comment 를 부르지 않는다
        self.assertEqual([c for c in calls if c[1:3] == ["issue", "comment"]], [])

    def test_comment_leak_notice_option(self):
        posted_body = []

        def fake_run(argv, cwd=None, stdin=None):
            if argv[1] == "stdin":
                return 0, "[]"
            if argv[1:3] == ["issue", "comment"]:
                p = pathlib.Path(argv[argv.index("--body-file") + 1])
                posted_body.append(p.read_text(encoding="utf-8"))
                return 0, "https://github.com/org/repo/issues/1#issuecomment-111\n"
            return 0, ""

        dec = leak.comment(self.wt, issue_url="https://github.com/org/repo/issues/1",
                           leak_notice=True, run=fake_run, git=lambda *a: "",
                           user_rules_path=self.user_rules)
        self.assertEqual(dec["action"], "posted")
        self.assertTrue(posted_body)
        self.assertIn(self.wt.name, posted_body[0])
        self.assertNotIn(str(self.wt), posted_body[0])

    def test_comment_both_or_neither_body_file_and_leak_notice_raises(self):
        with self.assertRaises(leak.LeakError):
            leak.comment(self.wt, issue_url="https://github.com/org/repo/issues/1",
                         body_file=None, leak_notice=False, run=lambda *a: 0, git=lambda *a: "")

        with self.assertRaises(leak.LeakError):
            leak.comment(self.wt, issue_url="https://github.com/org/repo/issues/1",
                         body_file="f.md", leak_notice=True, run=lambda *a: 0, git=lambda *a: "")


class TestPublishCLI(unittest.TestCase):
    def test_publish_comment_requires_one_of_body_file_or_leak_notice(self):
        import subprocess
        import sys
        # 둘 다 없을 때 종료코드 2
        r1 = subprocess.run([sys.executable, str(PLUGIN_ROOT / "scripts/relay_cli.py"), "publish", "comment",
                             "--worktree", ".", "--issue", "https://github.com/org/repo/issues/1"],
                            capture_output=True, text=True)
        self.assertEqual(r1.returncode, 2)

        # 둘 다 있을 때 종료코드 2
        r2 = subprocess.run([sys.executable, str(PLUGIN_ROOT / "scripts/relay_cli.py"), "publish", "comment",
                             "--worktree", ".", "--issue", "https://github.com/org/repo/issues/1",
                             "--body-file", "body.md", "--leak-notice"],
                            capture_output=True, text=True)
        self.assertEqual(r2.returncode, 2)


if __name__ == "__main__":
    unittest.main()
