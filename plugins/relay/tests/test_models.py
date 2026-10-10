# -*- coding: utf-8 -*-
import json
import pathlib
import tempfile
import unittest

import helpers  # noqa: F401
from relaylib import models


class Parse(unittest.TestCase):
    def test_valid(self):
        c = models.parse(json.dumps({"$comment": "x", "reviewer": {"model": "gpt-9", "effort": "high"}, "implementer": {"model": None, "effort": ""}}))
        self.assertEqual(c, {"reviewer": {"model": "gpt-9", "effort": "high"}, "implementer": {}})

    def test_rejects_typos(self):
        for bad in ({"reviwer": {}}, {"reviewer": {"modle": "x"}}, {"reviewer": "gpt"}, []):
            with self.assertRaises(models.ModelsError):
                models.parse(json.dumps(bad))

    def test_rejects_bad_json(self):
        with self.assertRaises(models.ModelsError):
            models.parse("{nope")

    def test_effort_set_depends_on_role(self):
        models.parse(json.dumps({"reviewer": {"effort": "minimal"}}))
        with self.assertRaises(models.ModelsError):
            models.parse(json.dumps({"coordinator": {"effort": "minimal"}}))

    def test_model_charset(self):
        for ok in ("opus", "gemini-3.8-flash", "claude-sonnet-5-5", "ns/model:tag"):
            models.check_value("reviewer", "model", ok)
        for bad in ("a b", "x;y", "-rf", "$(x)", "", None, 5):
            with self.assertRaises(models.ModelsError):
                models.check_value("reviewer", "model", bad)


class Layers(unittest.TestCase):
    def setUp(self):
        self._d = tempfile.TemporaryDirectory()
        self.base = pathlib.Path(self._d.name)
        self.user = self.base / "user.json"
        self.repo = self.base / "repo"
        (self.repo / ".ai").mkdir(parents=True)

    def tearDown(self):
        self._d.cleanup()

    def test_missing_files_mean_no_config(self):
        self.assertEqual(models.load_all(self.repo, self.user), ({}, []))

    def test_repo_overrides_user_per_field(self):
        self.user.write_text(json.dumps({"reviewer": {"model": "u-model", "effort": "low"}, "designer": {"model": "opus"}}), encoding="utf-8")
        (self.repo / ".ai" / "relay-models.json").write_text(json.dumps({"reviewer": {"effort": "xhigh"}}), encoding="utf-8")
        cfg, used = models.load_all(self.repo, self.user)
        self.assertEqual(cfg["reviewer"], {"model": "u-model", "effort": "xhigh"})
        self.assertEqual(cfg["designer"], {"model": "opus"})
        self.assertEqual(len(used), 2)

    def test_broken_file_names_its_path(self):
        self.user.write_text("{", encoding="utf-8")
        with self.assertRaises(models.ModelsError) as cm:
            models.load_all(self.repo, self.user)
        self.assertIn("user.json", str(cm.exception))


class Resolve(unittest.TestCase):
    def test_defaults(self):
        self.assertEqual(models.resolve("reviewer", {}), {"model": None, "effort": "high", "configured": []})
        self.assertIsNone(models.resolve("implementer", {})["effort"])

    def test_configured_wins(self):
        r = models.resolve("coordinator", {"coordinator": {"effort": "low"}})
        self.assertEqual((r["effort"], r["configured"]), ("low", ["effort"]))


AGY = ("Fetching available models...\ngemini-3.8-flash-high\tA\ngemini-3.8-flash-low\tA\n"
       "gemini-3.1-pro-high\tB\ngemini-3.1-pro-low\tB\ngpt-oss-120b-medium\tC\n")


def agy_status(model, effort):
    return models.check_agy(model, effort, AGY)[0]


class AgyCheck(unittest.TestCase):
    def test_parse(self):
        bases, ids = models.parse_agy_models(AGY)
        self.assertEqual(bases["gemini-3.1-pro"], ["high", "low"])
        self.assertIn("gpt-oss-120b-medium", ids)
        self.assertNotIn("Fetching available models...", ids)

    def test_results(self):
        self.assertEqual(agy_status(None, None), "ok")
        self.assertEqual(agy_status(None, "high"), "ok")                  # 실측: agy --effort high 단독은 통과
        self.assertEqual(agy_status("gemini-3.8-flash", "low"), "ok")
        self.assertEqual(agy_status("gemini-3.8-flash-low", None), "ok")
        self.assertEqual(agy_status("gemini-3.8-flash-low", "low"), "fail")   # 실측: conflicts with --effort
        self.assertEqual(agy_status("gemini-3.1-pro", "xhigh"), "fail")       # 실측: has no "xhigh" effort
        self.assertEqual(agy_status("bogus", None), "fail")

    def test_unreadable_listing_only_warns(self):
        self.assertEqual(models.check_agy("x", None, "")[0], "warn")


if __name__ == "__main__":
    unittest.main()
