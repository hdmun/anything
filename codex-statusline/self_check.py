"""Run real MCP stdio requests against the repository or installed provider."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


provider = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name("statusline.py")
uri = "ui://codex-statusline/footer"


def read(state):
    return {"uri": uri, "_meta": {"com.openai/codex-statusline-state": state}}


def snapshot(thread_id, model, cwd, percentage):
    return {"thread": {"id": thread_id, "model": {"display_name": model, "reasoning_level": "high"},
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
rich = snapshot("rich", "GPT-6", "C:/work", 85)
rich["thread"]["usage"]["context"].update(used_tokens=124000, context_window_size=200000)
rich["thread"]["usage"]["cost"] = {"total_cost_usd": 1.23}
rich["account"] = {"rate_limits": [{"limit_id": "codex", "limit_name": None,
    "primary_limit": {"used_percent": 30, "window_minutes": 300,
                      "resets_at": time.time() + 7800},
    "secondary_limit": {"used_percent": 110, "window_minutes": 10080, "resets_at": None}}]}
requests.append(("resources/read", read(rich)))
requests.append(("resources/read", read(snapshot("next", "GPT-6", "C:/work", 1))))
home = Path(tempfile.mkdtemp(prefix="codex-statusline-check-"))  # never the real ~/.codex
cache = home / "statusline-rate-limits.json"


def run(requests):
    wire = [{"jsonrpc": "2.0", "id": i, "method": method, "params": params}
            for i, (method, params) in enumerate(requests)]
    wire.insert(1, {"jsonrpc": "2.0", "method": "notifications/initialized"})
    result = subprocess.run(
        [sys.executable, "-u", str(provider)],
        input="".join(json.dumps(request) + "\n" for request in wire),
        capture_output=True, text=True, encoding="utf-8", timeout=5, check=True,
        env={**os.environ, "CODEX_HOME": str(home)},
    )
    assert not result.stderr, result.stderr
    return [json.loads(line) for line in result.stdout.splitlines()]


def labels_of(reply):
    tree = json.loads(reply["result"]["contents"][0]["text"])
    return [child["children"][0] for child in tree["children"] if isinstance(child, dict)]


replies = run(requests)
assert [reply["id"] for reply in replies] == list(range(len(requests)))
assert replies[0]["result"]["capabilities"] == {"tools": {}, "resources": {}}
tool, = replies[1]["result"]["tools"]
assert tool["name"] == "statusline"
assert tool["_meta"]["openai/ui"]["entrypoints"] == [
    {"type": "statusline", "resourceUri": uri}
]
expected = [
    ["🤖 GPT-6 (high)", "📁 one", "🧠 ████░░░░░░ 42%"],
    ["🤖 GPT-6", "📁 one"],
    ["🤖 GPT-6 mini (high)", "📁 two", "🧠 ░░░░░░░░░░ 0%"],
    [],
]
for reply, labels in zip(replies[2:6], expected):
    resource, = reply["result"]["contents"]
    assert resource["uri"] == uri
    assert resource["mimeType"] == "application/json"
    tree = json.loads(resource["text"])
    assert tree["type"] == "row" and tree["props"]["gap"] == 1
    assert [child["children"][0] for child in tree["children"] if isinstance(child, dict)] == labels
assert replies[6]["error"]["code"] == -32602
tree = json.loads(replies[7]["result"]["contents"][0]["text"])
items = [child for child in tree["children"] if isinstance(child, dict)]
labels = [child["children"][0] for child in items]
assert labels[:4] == ["🤖 GPT-6 (high)", "📁 work", "🧠 █████████░ 85%", "124k/200k"]
assert items[2]["props"]["color"] == "red"
assert labels[4].startswith("⏳ codex 5h0m 30% (🔄 2h")
assert labels[5:] == ["⏳ codex 7d0h 100%", "💰 $1.23"]
assert items[4]["props"]["color"] == "green"
assert items[5]["props"]["color"] == "red"
# no rate_limits in the snapshot -> last saved value from the cache
assert json.loads(cache.read_text(encoding="utf-8")) == rich["account"]["rate_limits"]
cached = labels_of(replies[8])
assert cached[3].startswith("⏳ codex 5h0m 30% (🔄 2h") and cached[4] == "⏳ codex 7d0h 100%"
# cached window whose reset time has passed -> 0%, no reset time
stale = json.loads(cache.read_text(encoding="utf-8"))
stale[0]["primary_limit"]["resets_at"] = time.time() - 60
cache.write_text(json.dumps(stale), encoding="utf-8")
assert labels_of(run([("initialize", {}), requests[2]])[1])[3:] == [
    "⏳ codex 5h0m 0%", "⏳ codex 7d0h 100%"]
# broken cache -> limits omitted, statusline still renders
cache.write_text("{broken", encoding="utf-8")
assert labels_of(run([("initialize", {}), requests[2]])[1]) == expected[0]
cache.unlink()
home.rmdir()
print("PASS: MCP handshake, tools/list, resource reads, missing optional fields, thread switch, invalid URI, rate limit cache")
