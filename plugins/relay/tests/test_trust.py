# -*- coding: utf-8 -*-
import json
import pathlib
import tempfile
import unittest

import helpers  # noqa: F401  (sys.path)
from relaylib import trust


class Normalize(unittest.TestCase):
    def test_slashes_become_backslashes(self):
        # worktree create 는 슬래시로 주지만 agy 의 기존 항목은 백슬래시다
        self.assertEqual(trust.normalize("C:/Users/x/orca/workspaces/p/T-001"), r"C:\Users\x\orca\workspaces\p\T-001")

    def test_trailing_separator_dropped(self):
        self.assertEqual(trust.normalize("C:/a/b/"), r"C:\a\b")


class AddRemove(unittest.TestCase):
    def test_add_new(self):
        s = {"model": "m", "trustedWorkspaces": [r"C:\old"]}
        self.assertTrue(trust.add(s, "C:/new"))
        self.assertEqual(s["trustedWorkspaces"], [r"C:\old", r"C:\new"])
        self.assertEqual(s["model"], "m")

    def test_add_creates_list(self):
        s = {}
        trust.add(s, "C:/new")
        self.assertEqual(s["trustedWorkspaces"], [r"C:\new"])

    def test_add_existing_is_noop_case_insensitive(self):
        s = {"trustedWorkspaces": [r"c:\users\X\T-001"]}
        self.assertFalse(trust.add(s, "C:/Users/x/T-001"))
        self.assertEqual(len(s["trustedWorkspaces"]), 1)

    def test_remove_all_matches(self):
        s = {"trustedWorkspaces": [r"C:\a\T-001", r"c:\A\t-001", r"C:\keep"]}
        self.assertEqual(trust.remove(s, "C:/a/T-001"), 2)
        self.assertEqual(s["trustedWorkspaces"], [r"C:\keep"])

    def test_remove_absent(self):
        s = {"trustedWorkspaces": [r"C:\keep"]}
        self.assertEqual(trust.remove(s, "C:/nope"), 0)


class Prune(unittest.TestCase):
    def test_only_dead_entries_under_relay_root(self):
        root = r"C:\Users\x\orca\workspaces"
        alive = {root + r"\p\T-002"}
        s = {"trustedWorkspaces": [
            root + r"\p\T-001",          # relay 소유 + 사라짐 → 제거
            root + r"\p\T-002",          # relay 소유 + 살아 있음 → 유지
            r"C:\Users\x\old-project",   # 사용자 항목 → 사라졌어도 유지
        ]}
        removed = trust.prune(s, root, exists=lambda p: p in alive)
        self.assertEqual(removed, [root + r"\p\T-001"])
        self.assertEqual(s["trustedWorkspaces"], [root + r"\p\T-002", r"C:\Users\x\old-project"])

    def test_root_match_is_case_insensitive_and_not_a_prefix_trick(self):
        root = r"C:\ws"
        s = {"trustedWorkspaces": [r"c:\WS\p\T-1", r"C:\ws-other\T-1"]}
        removed = trust.prune(s, root, exists=lambda p: False)
        self.assertEqual(removed, [r"c:\WS\p\T-1"])


class FileIO(unittest.TestCase):
    def test_roundtrip_preserves_other_keys_and_unicode(self):
        with tempfile.TemporaryDirectory() as d:
            p = pathlib.Path(d) / "settings.json"
            p.write_text(json.dumps({"model": "Gemini 3.8 Flash (Medium)", "note": "한글"}, ensure_ascii=False), encoding="utf-8")
            s = trust.load(p)
            trust.add(s, "C:/w/T-1")
            trust.save(p, s)
            back = json.loads(p.read_text(encoding="utf-8"))
            self.assertEqual(back["note"], "한글")
            self.assertEqual(back["trustedWorkspaces"], [r"C:\w\T-1"])


if __name__ == "__main__":
    unittest.main()
