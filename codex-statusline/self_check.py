"""Run real MCP stdio requests against the repository or installed provider."""

import json
from pathlib import Path
import subprocess
import sys


provider = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("statusline.py")
uri = "ui://codex-statusline/footer"


def read(state):
    return {"uri": uri, "_meta": {"com.openai/codex-statusline-state": state}}


def snapshot(thread_id, model, cwd, percentage):
    return {"thread": {"id": thread_id, "model": {"display_name": model},
                       "workspace": {"cwd": cwd},
                       "usage": {"context": {"used_percentage": percentage}}}}


requests = [
    ("initialize", {}),
    ("tools/list", {}),
    ("resources/read", read(snapshot("one", "GPT-6", "C:/작업/one", 42.4))),
    ("resources/read", read({"thread": {"model": {"display_name": "GPT-6"},
                                       "workspace": {"cwd": "C:/one"},
                                       "usage": {"context": {}}}})),
    ("resources/read", read(snapshot("two", "GPT-6 mini", "D:/two", 0))),
    ("resources/read", read({})),
    ("resources/read", {"uri": "ui://unknown/footer"}),
]
wire = [{"jsonrpc": "2.0", "id": i, "method": method, "params": params}
        for i, (method, params) in enumerate(requests)]
wire.insert(1, {"jsonrpc": "2.0", "method": "notifications/initialized"})
result = subprocess.run(
    [sys.executable, "-u", str(provider)],
    input="".join(json.dumps(request) + "\n" for request in wire),
    capture_output=True, text=True, encoding="utf-8", timeout=5, check=True,
)
assert not result.stderr, result.stderr
replies = [json.loads(line) for line in result.stdout.splitlines()]
assert [reply["id"] for reply in replies] == list(range(len(requests)))
assert replies[0]["result"]["capabilities"] == {"tools": {}, "resources": {}}
tool, = replies[1]["result"]["tools"]
assert tool["name"] == "statusline"
assert tool["_meta"]["openai/ui"]["entrypoints"] == [
    {"type": "statusline", "resourceUri": uri}
]
expected = [
    ["GPT-6", "C:/작업/one", "컨텍스트 42%"],
    ["GPT-6", "C:/one", "컨텍스트 —"],
    ["GPT-6 mini", "D:/two", "컨텍스트 0%"],
    ["Codex", "—", "컨텍스트 —"],
]
for reply, labels in zip(replies[2:6], expected):
    resource, = reply["result"]["contents"]
    assert resource["uri"] == uri
    assert resource["mimeType"] == "application/json"
    tree = json.loads(resource["text"])
    assert tree["type"] == "row" and tree["props"]["gap"] == 1
    assert [child["children"][0] for child in tree["children"]] == labels
assert replies[6]["error"]["code"] == -32602
print("PASS: MCP handshake, tools/list, resource reads, missing optional fields, thread switch, invalid URI")
