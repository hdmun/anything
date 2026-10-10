# -*- coding: utf-8 -*-
"""git 이 필요한 CLI 경로 — diff-guard, review-branch 의 구현 라운드 세기, trust 파일 조작."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

from helpers import SCRIPTS


def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


def cli(*args):
    return subprocess.run([sys.executable, str(SCRIPTS / "relay_cli.py"), *args], capture_output=True)


class GitRepoCase(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.repo = pathlib.Path(self._d.name)
        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "t@example.com")
        git(self.repo, "config", "user.name", "t")
        git(self.repo, "config", "core.autocrlf", "false")
        (self.repo / "a.txt").write_text("a\n", encoding="utf-8")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", "base")
        self.base = git(self.repo, "rev-parse", "HEAD")

    def tearDown(self):
        self._d.cleanup()

    def commit(self, name, msg):
        (self.repo / name).write_text(name + "\n", encoding="utf-8")
        git(self.repo, "add", ".")
        git(self.repo, "commit", "-q", "-m", msg)


class DiffGuard(GitRepoCase):
    def test_empty_range_fails(self):
        r = cli("diff-guard", "--worktree", str(self.repo), "--base", self.base)
        self.assertEqual(r.returncode, 1)
        self.assertTrue(r.stderr.strip())

    def test_nonempty_range_passes(self):
        self.commit("b.txt", "feat(T-1): b\n\nImplemented-by: agy/x")
        r = cli("diff-guard", "--worktree", str(self.repo), "--base", self.base)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_bad_base_is_input_error(self):
        r = cli("diff-guard", "--worktree", str(self.repo), "--base", "deadbeef")
        self.assertEqual(r.returncode, 2)


class ReviewBranchCli(GitRepoCase):
    def test_counts_implemented_by_trailers(self):
        self.commit("b.txt", "feat(T-004): b\n\nImplemented-by: agy/Gemini 3.8 Flash (Medium)")
        self.commit("r.json", "review(T-004): r1 changes_requested\n\nReviewed-by: codex/gpt-6-luna")
        self.commit("c.txt", "feat(T-004): fix\n\nImplemented-by: agy/Gemini 3.8 Flash (Medium)")
        reviews = self.repo / ".ai" / "reviews"
        reviews.mkdir(parents=True)
        for n, s in ((1, "a"), (2, "b"), (3, "c")):
            (reviews / ("T-004.r%d.json" % n)).write_text(json.dumps({
                "taskId": "T-004", "verdict": "changes_requested",
                "findings": [{"severity": "MAJOR", "file": "x", "summary": s, "repro": "r"}]}), encoding="utf-8")
        r = cli("review-branch", "--task", "T-004", "--worktree", str(self.repo), "--base", self.base)
        self.assertEqual(r.returncode, 0, r.stderr)
        d = json.loads(r.stdout)
        # 구현 2 + 리뷰 3 = 5 → 한도 안. 리뷰 3회도 '초과'는 아니다
        self.assertEqual(d["action"], "fix_round")
        self.assertEqual(d["impl_rounds"], 2)
        self.assertEqual(d["review_rounds"], 3)

    def test_missing_reviews_is_input_error(self):
        r = cli("review-branch", "--task", "T-004", "--worktree", str(self.repo), "--base", self.base)
        self.assertEqual(r.returncode, 2)


class CommitGuard(GitRepoCase):
    def test_attributed_commits_pass(self):
        self.commit("b.txt", "feat(T-004): b\n\nImplemented-by: agy/x")
        self.commit("r.json", "review(T-004): r1 pass\n\nReviewed-by: codex/m")
        r = cli("commit-guard", "--worktree", str(self.repo), "--base", self.base)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_worker_self_commit_fails(self):
        # 실측(T-004 dd95130): agy 가 git commit 권한으로 직접 커밋 — 트레일러 없음
        self.commit("b.txt", "feat(T-004): b\n\nImplemented-by: agy/x")
        self.commit("c.txt", "fix(analysis): 무작위 입력 검사 추가")
        r = cli("commit-guard", "--worktree", str(self.repo), "--base", self.base)
        self.assertEqual(r.returncode, 1)
        err = r.stderr.decode("utf-8")
        self.assertIn("fix(analysis)", err)
        self.assertNotIn("feat(T-004)", err)

    def test_merge_commits_ignored(self):
        git(self.repo, "checkout", "-q", "-b", "side")
        self.commit("s.txt", "feat(T-1): s\n\nImplemented-by: agy/x")
        git(self.repo, "checkout", "-q", "main")
        self.commit("m.txt", "feat(T-1): m\n\nImplemented-by: agy/x")
        git(self.repo, "merge", "-q", "--no-ff", "side", "-m", "Merge branch 'side'")
        r = cli("commit-guard", "--worktree", str(self.repo), "--base", self.base)
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_empty_range_passes(self):
        self.assertEqual(cli("commit-guard", "--worktree", str(self.repo), "--base", self.base).returncode, 0)


class OrcaCli(unittest.TestCase):
    FIX = pathlib.Path(__file__).parent / "fixtures" / "orca"

    def test_startup_reads_file(self):
        r = cli("startup", "--response", str(self.FIX / "worker-start-readiness-failed.json"))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(r.stdout)["action"], "new_task")

    def test_startup_reads_stdin(self):
        data = (self.FIX / "worker-start-no-dispatch.json").read_bytes()
        r = subprocess.run([sys.executable, str(SCRIPTS / "relay_cli.py"), "startup", "--response", "-"], input=data, capture_output=True)
        self.assertEqual(json.loads(r.stdout)["action"], "lookup_dispatch")

    def test_readiness_cli(self):
        with tempfile.TemporaryDirectory() as d:
            log = pathlib.Path(d) / "cli.log"
            log.write_text("OAuth: authenticated successfully as x\n", encoding="utf-8")
            r = cli("readiness", "--agent", "antigravity", "--screen", str(self.FIX / "agy-screen-misordered.txt"),
                    "--agy-log", str(log), "--retries", "3", "--command", "$null=1; agy")
            self.assertEqual(json.loads(r.stdout)["action"], "recreate_terminal")

    def test_readiness_agy_requires_command(self):
        with tempfile.TemporaryDirectory() as d:
            log = pathlib.Path(d) / "cli.log"
            log.write_text("OAuth: authenticated successfully as x\n", encoding="utf-8")
            r = cli("readiness", "--agent", "antigravity", "--screen", str(self.FIX / "agy-screen-misordered.txt"),
                    "--agy-log", str(log), "--retries", "0")
            self.assertEqual(r.returncode, 2)
            self.assertIn("--command", r.stderr.decode("utf-8"))

    def test_readiness_reads_box_drawing_json_as_utf8(self):
        # T-007 보고: 박스 문자가 든 screen.json 을 cp949 로 읽는가 → relay_cli 는 utf-8 로 읽는다
        tail = ["▄▀▀▄  Antigravity CLI 1.3.3", "─" * 10, ">", "─" * 10, "Gemini 3.8 Flash (Medium) │ Idle"]
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "screen.json"
            p.write_text(json.dumps({"ok": True, "result": {"terminal": {"tail": tail}}}, ensure_ascii=False), encoding="utf-8")
            env = {k: v for k, v in os.environ.items() if k not in ("PYTHONUTF8", "PYTHONIOENCODING")}
            r = subprocess.run([sys.executable, str(SCRIPTS / "relay_cli.py"), "readiness", "--agent", "codex",
                                "--screen", str(p), "--retries", "0"], capture_output=True, env=env)
            self.assertEqual(r.returncode, 0, r.stderr.decode("utf-8", "replace"))
            self.assertNotIn(b"UnicodeDecodeError", r.stderr)

    def test_readiness_accepts_orca_json_screen(self):
        # orca terminal read --screen --json 출력을 그대로 넘겨도 된다
        tail = (self.FIX / "codex-screen-ready.txt").read_text(encoding="utf-8").splitlines()
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "screen.json"
            p.write_text(json.dumps({"ok": True, "result": {"terminal": {"tail": tail}}}), encoding="utf-8")
            r = cli("readiness", "--agent", "codex", "--screen", str(p), "--retries", "3")
            self.assertEqual(json.loads(r.stdout)["action"], "recreate_terminal")

    def test_liveness_cli(self):
        with tempfile.TemporaryDirectory() as d:
            t = pathlib.Path(d) / "term.json"
            t.write_text(json.dumps({"ok": True, "result": {"terminal": {"agentWait": None, "lastOutputAt": 1000}}}), encoding="utf-8")
            r = cli("liveness", "--worker", str(self.FIX / "worker-list-entry.json"), "--terminal", str(t),
                    "--role", "implementer", "--now", str(1000 + 6 * 60_000))
            self.assertEqual(json.loads(r.stdout)["reason"], "stalled")

    def test_model_reviewer_cli(self):
        with tempfile.TemporaryDirectory() as d:
            c = pathlib.Path(d) / "config.toml"
            c.write_text('model = "gpt-6-luna"\ncheck_for_update_on_startup = false\n[tui]\nterminal_title = ["app-name"]\n', encoding="utf-8")
            none = str(pathlib.Path(d) / "no-user.json")
            r = cli("model", "reviewer", "--config", str(c), "--repo", d, "--user-config", none)
            out = json.loads(r.stdout)
            self.assertEqual((out["action"], out["reason"]), ("human", "reviewer_model_unset"))   # config.toml 의 model 은 쓰지 않는다

    def test_model_reviewer_cli_reads_both_layers(self):
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d)
            c = d / "config.toml"
            c.write_text('model = "gpt-6-luna"\ncheck_for_update_on_startup = false\n[tui]\nterminal_title = ["app-name"]\n', encoding="utf-8")
            u = d / "user.json"
            u.write_text(json.dumps({"reviewer": {"model": "gpt-9", "effort": "low"}}), encoding="utf-8")
            (d / ".ai").mkdir()
            (d / ".ai" / "relay-models.json").write_text(json.dumps({"reviewer": {"effort": "xhigh"}}), encoding="utf-8")
            out = json.loads(cli("model", "reviewer", "--config", str(c), "--repo", str(d), "--user-config", str(u)).stdout)
            self.assertEqual((out["model"], out["effort"]), ("gpt-9", "xhigh"))

    def test_model_bad_file_exits_2(self):
        with tempfile.TemporaryDirectory() as d:
            u = pathlib.Path(d) / "user.json"
            u.write_text(json.dumps({"coordinator": {"model": "a b"}}), encoding="utf-8")
            r = cli("model", "coordinator", "--repo", d, "--user-config", str(u))
            self.assertEqual(r.returncode, 2)
            self.assertIn("user.json", r.stderr.decode("utf-8"))

    def test_model_session_role(self):
        with tempfile.TemporaryDirectory() as d:
            u = pathlib.Path(d) / "user.json"
            u.write_text(json.dumps({"designer": {"model": "opus", "effort": "max"}}), encoding="utf-8")
            out = json.loads(cli("model", "designer", "--repo", d, "--user-config", str(u)).stdout)
            self.assertEqual(out["command"], "claude --model opus --effort max")


class ValidateCli(unittest.TestCase):
    def test_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "T-004.r1.json"
            p.write_text(json.dumps({"taskId": "T-004", "verdict": "pass", "findings": []}), encoding="utf-8")
            self.assertEqual(cli("validate-review", str(p)).returncode, 0)
            p.write_text(json.dumps({"taskId": "T-005", "verdict": "pass", "findings": []}), encoding="utf-8")
            r = cli("validate-review", str(p))
            self.assertEqual(r.returncode, 1)
            self.assertIn("taskId", r.stderr.decode("utf-8"))
            p.write_text("{not json", encoding="utf-8")
            self.assertEqual(cli("validate-review", str(p)).returncode, 1)


class TrustCli(unittest.TestCase):
    def test_add_remove_roundtrip(self):
        with tempfile.TemporaryDirectory() as d:
            s = pathlib.Path(d) / "settings.json"
            s.write_text(json.dumps({"model": "m"}), encoding="utf-8")
            r = cli("trust", "add", "C:/w/T-1", "--settings", str(s))
            self.assertEqual(r.returncode, 0)
            self.assertIn("added", r.stdout.decode())
            self.assertIn("already", cli("trust", "add", "C:/w/T-1", "--settings", str(s)).stdout.decode())
            self.assertIn("removed", cli("trust", "remove", "C:/w/T-1", "--settings", str(s)).stdout.decode())
            self.assertEqual(json.loads(s.read_text(encoding="utf-8"))["trustedWorkspaces"], [])

    def test_prune_is_dry_run_by_default(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d) / "ws"
            (root / "p" / "alive").mkdir(parents=True)
            dead = str(root / "p" / "dead")
            s = pathlib.Path(d) / "settings.json"
            s.write_text(json.dumps({"trustedWorkspaces": [dead, str(root / "p" / "alive")]}), encoding="utf-8")
            r = cli("trust", "prune", "--root", str(root), "--settings", str(s))
            self.assertEqual(r.returncode, 0)
            self.assertIn("dead", r.stdout.decode())
            self.assertEqual(len(json.loads(s.read_text(encoding="utf-8"))["trustedWorkspaces"]), 2)
            cli("trust", "prune", "--root", str(root), "--settings", str(s), "--apply")
            self.assertEqual(json.loads(s.read_text(encoding="utf-8"))["trustedWorkspaces"], [str(root / "p" / "alive")])


if __name__ == "__main__":
    unittest.main()
