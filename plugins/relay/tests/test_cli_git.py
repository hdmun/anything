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
