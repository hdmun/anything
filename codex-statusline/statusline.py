"""A Codex statusline provider using newline-delimited MCP over stdio."""

import json
import ntpath
import os
from pathlib import Path
import sys
import time


URI = "ui://codex-statusline/footer"
TOOL = {
    "name": "statusline",
    "title": "Codex 사용량 statusline",
    "description": "Show the model, workspace, context, limits and cost.",
    "inputSchema": {"type": "object", "properties": {}},
    "_meta": {
        "openai/ui": {"entrypoints": [{"type": "statusline", "resourceUri": URI}]}
    },
}


def cache_path():
    """Per-account file: CODEX_HOME, else the install dir <CODEX_HOME>/statusline/, else ~/.codex."""
    if home := os.environ.get("CODEX_HOME"):
        return Path(home) / "statusline-rate-limits.json"
    here = Path(__file__).resolve().parent
    base = here.parent if here.name == "statusline" else Path.home() / ".codex"
    return base / "statusline-rate-limits.json"


_written = None


def rate_limits(state):
    """Return (limits, from_cache). Save fresh limits only when they change; ignore I/O errors."""
    global _written
    limits = state.get("account", {}).get("rate_limits")
    if limits:
        text = json.dumps(limits, ensure_ascii=False, sort_keys=True)
        if text != _written:
            try:
                cache_path().write_text(text, encoding="utf-8")
                _written = text
            except OSError:
                pass
        return limits, False
    try:
        cached = json.loads(cache_path().read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return [], False
    if not isinstance(cached, list):
        return [], False
    return [limit for limit in cached if isinstance(limit, dict)], True


def level(used):
    return "red" if used >= 80 else "yellow" if used >= 50 else "green"


def tokens(value):
    if value >= 1_000_000:
        return f"{value / 1_000_000:.1f}".rstrip("0").rstrip(".") + "M"
    return f"{value / 1000:.0f}k" if value >= 1000 else str(value)


def span(seconds):
    minutes = max(0, int(seconds)) // 60
    days, hours = divmod(minutes // 60, 24)
    if days:
        return f"{days}d{hours}h"
    return f"{hours}h{minutes % 60}m" if hours else f"{minutes}m"


def render(state):
    """Use the displayed thread's snapshot; limits fall back to the cache; omit unavailable values."""
    thread = state.get("thread", {})
    children = []

    def add(label, color):
        if children:
            children.append("|")
        children.append({"type": "text", "props": {"color": color}, "children": [label]})

    model = thread.get("model", {})
    if model.get("display_name"):
        label = "🤖 " + model["display_name"]
        if model.get("reasoning_level"):
            label += f" ({model['reasoning_level']})"
        add(label, "status-model")
    if cwd := thread.get("workspace", {}).get("cwd"):
        add("📁 " + (ntpath.basename(cwd.rstrip("/\\")) or cwd), "status-path")
    usage = thread.get("usage", {})
    context = usage.get("context", {})
    percentage = context.get("used_percentage")
    if percentage is not None:
        filled = int(max(0, min(100, percentage)) / 10 + 0.5)
        add(f"🧠 {'█' * filled}{'░' * (10 - filled)} {percentage:.0f}%", level(percentage))
    used, size = context.get("used_tokens"), context.get("context_window_size")
    if used is not None and size is not None:
        add(f"{tokens(used)}/{tokens(size)}", "status-metadata")
    limits, from_cache = rate_limits(state)
    now = time.time()
    for limit in limits:
        for key in ("primary_limit", "secondary_limit"):
            window = limit.get(key)
            if not window:
                continue
            name = limit.get("limit_name") or limit.get("limit_id") or "한도"
            duration = window.get("window_minutes")
            if duration is not None:
                name += " " + span(duration * 60)
            used = max(0, min(100, window["used_percent"]))
            resets_at = window.get("resets_at")
            if from_cache and resets_at is not None and resets_at <= now:
                used, resets_at = 0, None  # cached window already reset
            label = f"⏳ {name} {used:.0f}%"
            if resets_at is not None:
                label += f" (🔄 {span(resets_at - now)})"
            add(label, level(used))
    cost = usage.get("cost", {}).get("total_cost_usd")
    if cost is not None:
        add(f"💰 ${cost:.2f}", "green")
    return {"type": "row", "props": {"gap": 1, "wrap": "wrap"}, "children": children}


def respond(method, params):
    if method == "initialize":
        return {
            "protocolVersion": "2025-06-18",
            "capabilities": {"tools": {}, "resources": {}},
            "serverInfo": {"name": "codex-statusline", "version": "1.0"},
        }
    if method == "ping":
        return {}
    if method == "tools/list":
        return {"tools": [TOOL]}
    if method == "tools/call":
        if params.get("name") != TOOL["name"]:
            raise ValueError("Unknown tool name")
        return {
            "content": [{"type": "text", "text": f"The statusline resource is {URI}."}]
        }
    if method == "resources/list":
        return {
            "resources": [
                {"name": "footer", "uri": URI, "mimeType": "application/json"}
            ]
        }
    if method == "resources/templates/list":
        return {"resourceTemplates": []}
    if method == "resources/read":
        if params.get("uri") != URI:
            raise ValueError("Unknown resource URI")
        state = params.get("_meta", {}).get("com.openai/codex-statusline-state", {})
        return {
            "contents": [
                {
                    "uri": URI,
                    "mimeType": "application/json",
                    "text": json.dumps(render(state), ensure_ascii=False),
                }
            ]
        }
    raise KeyError(method)


def main():
    for line in sys.stdin.buffer:
        reply = {"jsonrpc": "2.0", "id": None}
        try:
            request = json.loads(line)
            if not isinstance(request, dict) or not isinstance(
                request.get("method"), str
            ):
                reply["error"] = {"code": -32600, "message": "Invalid request"}
            elif "id" not in request:
                continue
            else:
                reply["id"] = request["id"]
                reply["result"] = respond(request["method"], request.get("params", {}))
        except json.JSONDecodeError:
            reply["error"] = {"code": -32700, "message": "Parse error"}
        except KeyError:
            reply["error"] = {"code": -32601, "message": "Method not found"}
        except (TypeError, ValueError, AttributeError):
            reply["error"] = {"code": -32602, "message": "Invalid parameters"}
        print(json.dumps(reply), flush=True)


if __name__ == "__main__":
    main()
