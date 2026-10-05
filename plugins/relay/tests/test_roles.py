# -*- coding: utf-8 -*-
import json
import os
import subprocess
import sys
import unittest

from helpers import FULL_VARS, PLUGIN_ROOT, SCRIPTS, TempRepoCase

from relaylib import roles


def run(case, mode=None):
    return roles.run(case.plugin, case.repo, mode)


class InitOnFreshRepo(TempRepoCase):
    def test_plain_gitignore_without_block_does_not_block_init(self):
        # 회귀: 블록 없는 .gitignore 를 '이미 있고 다른 파일'로 보고 전부 거부했다 (종료코드 2)
        self.write_bytes(".gitignore", b"node_modules/\n")
        code, _ = run(self)
        self.assertEqual(code, 0)
        self.assertTrue(self.role("implementer").exists())
        self.assertTrue(self.role("reviewer").exists())
        gi = self.read_bytes(".gitignore").decode("utf-8")
        self.assertIn("node_modules/", gi)
        self.assertIn(roles.BEGIN, gi)
        self.assertIn("gate.log", gi)

    def test_no_gitignore_creates_one(self):
        code, _ = run(self)
        self.assertEqual(code, 0)
        self.assertIn(roles.BEGIN, self.read_bytes(".gitignore").decode("utf-8"))

    def test_second_run_is_noop(self):
        run(self)
        code, out = run(self, "check")
        self.assertEqual(code, 0, out)


class Check(TempRepoCase):
    def test_missing_block_is_drift(self):
        run(self)
        self.write_bytes(".gitignore", b"node_modules/\n")
        code, _ = run(self, "check")
        self.assertEqual(code, 1)

    def test_check_writes_nothing(self):
        code, _ = run(self, "check")
        self.assertEqual(code, 1)
        self.assertFalse(self.role("implementer").exists())
        self.assertFalse((self.repo / ".gitignore").exists())

    def test_stamp_only_difference_is_not_drift(self):
        run(self)
        p = self.role("implementer")
        text = p.read_text(encoding="utf-8")
        p.write_text(text.replace("relay-roles v", "relay-roles v0.0.0-old-", 1), encoding="utf-8")
        code, out = run(self, "check")
        self.assertEqual(code, 0)
        self.assertTrue(any("스탬프" in line for line in out))


class Conflicts(TempRepoCase):
    def test_edited_role_file_refuses_without_force_and_writes_nothing(self):
        run(self)
        self.role("reviewer").write_text("손으로 고친 내용\n", encoding="utf-8")
        self.write_bytes(".gitignore", b"node_modules/\n")
        code, _ = run(self)
        self.assertEqual(code, 2)
        self.assertEqual(self.role("reviewer").read_text(encoding="utf-8"), "손으로 고친 내용\n")
        self.assertEqual(self.read_bytes(".gitignore"), b"node_modules/\n")

    def test_force_overwrites(self):
        run(self)
        self.role("reviewer").write_text("손으로 고친 내용\n", encoding="utf-8")
        code, _ = run(self, "force")
        self.assertEqual(code, 0)
        self.assertIn("역할: 리뷰어", self.role("reviewer").read_text(encoding="utf-8"))

    def test_changed_block_is_rewritten_without_force(self):
        # 블록 안쪽은 relay 소유다 — gate_logs 를 바꾸면 그대로 반영한다
        run(self)
        v = dict(FULL_VARS, gate_logs=["gate.log", "vet.log"])
        self.write_vars(v)
        code, _ = run(self)
        self.assertEqual(code, 0)
        self.assertIn("vet.log", self.read_bytes(".gitignore").decode("utf-8"))


class Newlines(TempRepoCase):
    def test_crlf_gitignore_stays_crlf(self):
        self.write_bytes(".gitignore", b"node_modules/\r\ndist/\r\n")
        run(self)
        raw = self.read_bytes(".gitignore")
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""), "LF 단독 줄이 섞였다")

    def test_lf_gitignore_stays_lf(self):
        self.write_bytes(".gitignore", b"node_modules/\n")
        run(self)
        self.assertNotIn(b"\r\n", self.read_bytes(".gitignore"))

    def test_new_role_file_is_lf(self):
        run(self)
        self.assertNotIn(b"\r\n", self.role("implementer").read_bytes())

    def test_crlf_checkout_of_identical_role_is_not_drift(self):
        # core.autocrlf=true 체크아웃은 같은 내용을 CRLF 로 둔다
        run(self)
        for name in ("implementer", "reviewer"):
            p = self.role(name)
            p.write_bytes(p.read_bytes().replace(b"\n", b"\r\n"))
        code, out = run(self, "check")
        self.assertEqual(code, 0, out)

    def test_crlf_role_file_keeps_crlf_on_force(self):
        run(self)
        p = self.role("reviewer")
        p.write_bytes(b"old\r\ncontent\r\n")
        run(self, "force")
        raw = p.read_bytes()
        self.assertIn(b"\r\n", raw)
        self.assertNotIn(b"\n", raw.replace(b"\r\n", b""))


class Vars(TempRepoCase):
    def test_missing_required_key_is_reported(self):
        v = dict(FULL_VARS)
        del v["review_focus"]
        self.write_vars(v)
        with self.assertRaises(roles.RolesError) as cm:
            run(self)
        self.assertIn("review_focus", str(cm.exception))

    def test_empty_required_key_is_reported(self):
        self.write_vars(dict(FULL_VARS, gate_cmd_raw="  "))
        with self.assertRaises(roles.RolesError) as cm:
            run(self)
        self.assertIn("gate_cmd_raw", str(cm.exception))

    def test_missing_vars_file(self):
        (self.repo / ".ai" / "relay-roles.json").unlink()
        with self.assertRaises(roles.RolesError):
            run(self)

    def test_unknown_placeholder_in_template_is_reported(self):
        t = self.plugin / "templates" / "reviewer.md.tmpl"
        t.write_text(t.read_text(encoding="utf-8") + "\n{{NEW_KEY}}\n", encoding="utf-8")
        with self.assertRaises(roles.RolesError) as cm:
            run(self)
        self.assertIn("NEW_KEY", str(cm.exception))

    def test_real_templates_render_completely(self):
        run(self)
        text = self.role("implementer").read_text(encoding="utf-8")
        self.assertNotRegex(text, r"\{\{[A-Z_]+\}\}")
        self.assertIn("( go build ./... && go test ./... ) > gate.log", text)


class Cli(TempRepoCase):
    def _cli(self, script, *args, env_extra=None):
        env = dict(os.environ, **(env_extra or {}))
        return subprocess.run(
            [sys.executable, str(SCRIPTS / script), *args],
            capture_output=True, env=env,
        )

    def test_cp949_stdout_does_not_crash(self):
        # 회귀: Windows 파이프 출력이 cp949 라 '—' 가 든 diff 에서 UnicodeEncodeError 로 죽었다
        r = self._cli("relay_cli.py", "roles", "--plugin-root", str(self.plugin), "--repo", str(self.repo),
                      "--check", env_extra={"PYTHONIOENCODING": "cp949"})
        self.assertEqual(r.returncode, 1, r.stderr.decode("utf-8", "replace"))
        self.assertNotIn(b"UnicodeEncodeError", r.stderr)

    def test_bad_vars_exit_code_2(self):
        self.write_vars(dict(FULL_VARS, review_focus=""))
        r = self._cli("relay_cli.py", "roles", "--plugin-root", str(self.plugin), "--repo", str(self.repo))
        self.assertEqual(r.returncode, 2)
        self.assertIn("review_focus", r.stderr.decode("utf-8"))

    def test_legacy_render_roles_entry_still_works(self):
        # commands/init.md 와 기존 저장소 안내가 이 경로를 부른다
        r = self._cli("render_roles.py", "--plugin-root", str(self.plugin), "--repo", str(self.repo))
        self.assertEqual(r.returncode, 0, r.stderr.decode("utf-8", "replace"))
        self.assertTrue(self.role("implementer").exists())


if __name__ == "__main__":
    unittest.main()
