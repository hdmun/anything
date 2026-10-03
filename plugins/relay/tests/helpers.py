# -*- coding: utf-8 -*-
"""테스트 공용 도우미 — 임시 플러그인 루트와 임시 저장소를 만든다."""
import json
import pathlib
import shutil
import sys
import tempfile
import unittest

PLUGIN_ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = PLUGIN_ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

FULL_VARS = {
    "default_branch": "main",
    "rules_doc": "**[AGENTS.md](../../AGENTS.md)** — 규칙",
    "dep_rule": "표준 라이브러리만 쓴다",
    "gate_cmd_prose": "**`go build ./... && go test ./...`**",
    "gate_cmd_raw": "go build ./... && go test ./...",
    "gate_prep": "",
    "ask_extra": "",
    "gate_logs": ["gate.log"],
    "review_focus": "- 의존 방향",
}


class TempRepoCase(unittest.TestCase):
    """setUp 마다 실제 템플릿을 복사한 플러그인 루트와 빈 저장소를 만든다."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = pathlib.Path(self._tmp.name)
        self.plugin = base / "plugin"
        (self.plugin / ".claude-plugin").mkdir(parents=True)
        shutil.copy(PLUGIN_ROOT / ".claude-plugin" / "plugin.json", self.plugin / ".claude-plugin" / "plugin.json")
        shutil.copytree(PLUGIN_ROOT / "templates", self.plugin / "templates")
        self.repo = base / "repo"
        (self.repo / ".ai").mkdir(parents=True)
        self.write_vars(FULL_VARS)

    def tearDown(self):
        self._tmp.cleanup()

    def write_vars(self, v):
        (self.repo / ".ai" / "relay-roles.json").write_text(json.dumps(v, ensure_ascii=False), encoding="utf-8")

    def write_bytes(self, rel, data):
        p = self.repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
        return p

    def read_bytes(self, rel):
        return (self.repo / rel).read_bytes()

    def role(self, name):
        return self.repo / ".ai" / "roles" / (name + ".md")
