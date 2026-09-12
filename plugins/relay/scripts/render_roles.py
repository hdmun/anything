#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""relay 역할 파일을 플러그인 템플릿에서 생성한다.

  python render_roles.py --plugin-root <dir> [--repo <dir>] [--check | --force]

기본     : 파일이 없으면 생성. 이미 있고 내용이 다르면 거부하고 알린다.
--check  : 쓰지 않고 diff만 보고한다. 드리프트가 있으면 종료코드 1.
--force  : 덮어쓴다.

변수는 <repo>/.ai/relay-roles.json 에서 읽는다.
"""
import argparse, json, pathlib, sys, difflib

VARS_PATH = ".ai/relay-roles.json"
BEGIN = "# >>> relay gate logs >>>"
END = "# <<< relay gate logs <<<"


def load(plugin_root, repo):
    vp = repo / VARS_PATH
    if not vp.exists():
        sys.exit("변수 파일이 없습니다: %s\n먼저 /relay:init 으로 생성하세요." % vp)
    v = json.loads(vp.read_text(encoding="utf-8"))
    pj = json.loads((plugin_root / ".claude-plugin/plugin.json").read_text(encoding="utf-8"))
    v["version"] = pj["version"]
    return v


def render(plugin_root, v, name):
    t = (plugin_root / "templates" / (name + ".md.tmpl")).read_text(encoding="utf-8")
    gate_prep = v.get("gate_prep", "")
    if gate_prep and not gate_prep.endswith("\n"):
        gate_prep += "\n"
    ask_extra = v.get("ask_extra", "")
    if ask_extra and not ask_extra.endswith("\n"):
        ask_extra += "\n"
    sub = {
        "VERSION": v["version"],
        "RULES_DOC": v.get("rules_doc", ""),
        "DEP_RULE": v.get("dep_rule", ""),
        "GATE_CMD_PROSE": v.get("gate_cmd_prose", ""),
        "GATE_CMD_RAW": v.get("gate_cmd_raw", ""),
        "GATE_PREP": gate_prep,
        "ASK_EXTRA": ask_extra,
        "REVIEW_FOCUS": v.get("review_focus", ""),
        "DEFAULT_BRANCH": v.get("default_branch", "main"),
    }
    for k, val in sub.items():
        t = t.replace("{{%s}}" % k, val)
    left = [m for m in ("{{" + x + "}}" for x in sub) if m in t]
    if left:
        sys.exit("치환되지 않은 자리표시자: %s" % left)
    return t


def strip_stamp(text):
    """첫 줄이 생성 스탬프면 떼어낸다. 버전만 다른 것을 드리프트로 오인하지 않기 위해서다."""
    if text is None:
        return None
    first, _sep, rest = text.partition(chr(10))
    if first.startswith("<!-- relay-roles v") and first.rstrip().endswith("-->"):
        return rest
    return text


def gitignore_block(repo, logs):
    p = repo / ".gitignore"
    body = "\n".join([
        BEGIN,
        "# 게이트는 종료코드로 판정하므로 출력을 파일로 받는다. 그 산출물이 워크트리에",
        "# 남으면 리뷰에서 SPEC_VIOLATION 으로 잡힌다 (synapse T-004 실측).",
    ] + list(logs) + [END])
    old = p.read_text(encoding="utf-8") if p.exists() else ""
    if BEGIN in old and END in old:
        pre, rest = old.split(BEGIN, 1)
        _, post = rest.split(END, 1)
        new = pre + body + post
    else:
        new = (old.rstrip("\n") + "\n\n" if old.strip() else "") + body + "\n"
    return p, old, new


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plugin-root", required=True)
    ap.add_argument("--repo", default=".")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()

    plugin_root = pathlib.Path(a.plugin_root).resolve()
    repo = pathlib.Path(a.repo).resolve()
    v = load(plugin_root, repo)

    targets = []
    for name in ("implementer", "reviewer"):
        targets.append((repo / ".ai/roles" / (name + ".md"), render(plugin_root, v, name)))
    gp, gold, gnew = gitignore_block(repo, v.get("gate_logs", ["gate.log"]))
    targets.append((gp, gnew))

    drift, stamp_only = [], []
    for path, new in targets:
        cur = path.read_text(encoding="utf-8") if path.exists() else None
        if cur == new:
            continue
        if cur is not None and strip_stamp(cur) == strip_stamp(new):
            stamp_only.append((path, cur, new))
            continue
        drift.append((path, cur, new))

    if a.check:
        if not drift:
            if stamp_only:
                print("OK  내용 동일. 스탬프만 낡음 (%d개 파일) — 필요하면 --force 로 갱신" % len(stamp_only))
            else:
                print("OK  드리프트 없음 (relay-roles v%s)" % v["version"])
            return 0
        for path, cur, new in drift:
            print("\nDRIFT %s" % path)
            d = difflib.unified_diff((cur or "").splitlines(), new.splitlines(),
                                     "현재", "템플릿 v%s" % v["version"], lineterm="", n=1)
            for line in list(d)[:40]:
                print("  " + line)
        print("\n드리프트 %d개 파일. 템플릿이 옳으면 --force, 현재가 옳으면 템플릿을 고치세요." % len(drift))
        return 1

    if not drift and not stamp_only:
        print("변경 없음 (relay-roles v%s)" % v["version"])
        return 0

    for path, _c, new in stamp_only:
        path.write_text(new, encoding="utf-8")
        print("stamp  %s" % path)

    if not drift:
        print("스탬프만 갱신 (relay-roles v%s)" % v["version"])
        return 0

    existing = [p for p, cur, _ in drift if cur is not None]
    if existing and not a.force:
        print("이미 존재하고 내용이 다릅니다:")
        for p in existing:
            print("  " + str(p))
        print("--check 로 차이를 보거나 --force 로 덮어쓰세요.")
        return 2

    for path, _, new in drift:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(new, encoding="utf-8")
        print("wrote %s" % path)
    print("relay-roles v%s 적용" % v["version"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
