# -*- coding: utf-8 -*-
"""검증된 버전 기록(~/.relay/verified.json)과 smoke 의 기록 분기. 실제 홈·orca 는 쓰지 않는다."""
import argparse
import io
import json
import pathlib
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

import helpers  # noqa: F401 — sys.path 에 scripts 를 넣는다
import relay_cli
from relaylib import verified


class Load(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.tmp.name) / "verified.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_missing_file_gives_empty_keys(self):
        self.assertEqual(verified.load(self.path), {"codex": [], "antigravity": [], "orca": []})

    def test_missing_keys_filled_and_extra_ignored(self):
        self.path.write_text('{"codex": ["1.0.0"], "x": 1}', encoding="utf-8")
        self.assertEqual(verified.load(self.path), {"codex": ["1.0.0"], "antigravity": [], "orca": []})

    def test_bad_files_raise(self):
        for text in ("", "{nope", "[]", '{"codex": "1.0.0"}', '{"orca": [1]}'):
            self.path.write_text(text, encoding="utf-8")
            with self.assertRaises(verified.VerifiedError, msg=text):
                verified.load(self.path)


class Record(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.tmp.name) / "sub" / "verified.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_creates_parent_appends_without_duplicates(self):
        verified.record(self.path, {"antigravity": "1.0.0"})
        out = verified.record(self.path, {"antigravity": "1.1.0", "orca": "2.0.0"})
        out = verified.record(self.path, {"antigravity": "1.0.0"})
        self.assertEqual(out["antigravity"], ["1.0.0", "1.1.0"])
        self.assertEqual(out["orca"], ["2.0.0"])
        self.assertEqual(json.loads(self.path.read_text(encoding="utf-8")), out)

    def test_broken_file_is_not_overwritten(self):
        self.path.parent.mkdir(parents=True)
        self.path.write_text("{broken", encoding="utf-8")
        with self.assertRaises(verified.VerifiedError):
            verified.record(self.path, {"codex": "1.0.0"})
        self.assertEqual(self.path.read_text(encoding="utf-8"), "{broken")


def _run_result(version):
    def fake_run(argv, timeout=None):
        if argv[-1] == "--version":
            return relay_cli.RunResult(0 if version else 1, (version or ""), "")
        return relay_cli.RunResult(0, "{}", "")
    return fake_run


class SmokeRecord(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = pathlib.Path(self.tmp.name) / "verified.json"
        self.args = argparse.Namespace(dir="C:/w", repeat=1, run=None, model=None, effort=None)

    def tearDown(self):
        self.tmp.cleanup()

    def _smoke(self, passed, orca_version="1.4.265"):
        result = {"agent": "antigravity", "version": "1.5.13", "passed": passed, "run": "run_x"}
        versions = {"antigravity": "1.5.13", "orca": orca_version}
        buf = io.StringIO()
        with mock.patch.object(verified, "USER_PATH", self.path), \
             mock.patch.object(relay_cli, "_run", _run_result(None)), \
             mock.patch.object(relay_cli, "_cli_version", lambda ag: versions.get(ag)), \
             mock.patch.object(relay_cli.smoke, "run_workers", return_value=dict(result)), \
             redirect_stdout(buf):
            rc = relay_cli.cmd_smoke_worker(self.args, ("antigravity",), {})
        return rc, json.loads(buf.getvalue().strip().splitlines()[-1])

    def test_pass_records_agent_and_orca(self):
        rc, r = self._smoke(True)
        self.assertEqual(rc, 0)
        self.assertTrue(r["recorded"])
        self.assertFalse(r["verified"])
        v = verified.load(self.path)
        self.assertEqual((v["antigravity"], v["orca"]), (["1.5.13"], ["1.4.265"]))

    def test_fail_does_not_record(self):
        rc, r = self._smoke(False)
        self.assertEqual(rc, 1)
        self.assertFalse(r["recorded"])
        self.assertFalse(self.path.exists())

    def test_orca_version_none_records_without_orca(self):
        _, r = self._smoke(True, orca_version=None)
        self.assertTrue(r["recorded"])
        self.assertEqual(verified.load(self.path)["orca"], [])

    def test_record_called_without_orca_key(self):
        with mock.patch.object(verified, "record", wraps=verified.record) as rec:
            self._smoke(True, orca_version=None)
        self.assertEqual(rec.call_args.args[1], {"antigravity": "1.5.13"})


if __name__ == "__main__":
    unittest.main()
