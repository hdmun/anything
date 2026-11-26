import argparse, json, os, sys
from pathlib import Path

# 기록은 늘 UTF-8이지만 Windows 콘솔 기본(cp949)으로 확인 줄을 찍으면 한글이 깨져 보여 오진을 부른다.
sys.stdout.reconfigure(encoding="utf-8")

ap = argparse.ArgumentParser()
ap.add_argument("title")
ap.add_argument("--session")
a = ap.parse_args()

cfg = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
base = cfg / "projects"
if a.session:
    hits = list(base.glob(f"*/{a.session}.jsonl"))
else:
    cwd = os.getcwd()
    slug = "".join(c if c.isalnum() else "-" for c in cwd)
    d = base / slug
    hits = sorted(d.glob("*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)[:1] if d.is_dir() else []
if not hits:
    sys.exit("session file not found (pass --session <id>)")
f = hits[0]
entry = {"type": "custom-title", "customTitle": a.title, "sessionId": f.stem}
with open(f, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
print(f"renamed {f.stem[:8]} -> {a.title}")
