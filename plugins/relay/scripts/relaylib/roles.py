# -*- coding: utf-8 -*-
"""역할 파일(.ai/roles/*.md)과 .gitignore 게이트 로그 블록을 플러그인 템플릿에서 생성·검증한다.

모드
  None    : 없으면 만들고, 역할 파일이 이미 있고 내용이 다르면 아무것도 쓰지 않고 거부(2)
  "check" : 쓰지 않는다. 드리프트가 있으면 1
  "force" : 덮어쓴다

.gitignore 의 relay 블록은 relay 소유라 force 없이도 갱신한다. 블록 밖은 건드리지 않는다.
"""
import difflib
import json
import pathlib
import re

VARS_PATH = ".ai/relay-roles.json"
ROLE_NAMES = ("implementer", "reviewer")
BEGIN = "# >>> relay gate logs >>>"
END = "# <<< relay gate logs <<<"
STAMP_PREFIX = "<!-- relay-roles v"

# 비어 있으면 역할 파일이 빈 규칙을 담게 되는 키
REQUIRED_KEYS = ("rules_doc", "dep_rule", "gate_cmd_prose", "gate_cmd_raw", "review_focus")
PLACEHOLDER_RE = re.compile(r"\{\{[A-Z_]+\}\}")


class RolesError(Exception):
    """입력(변수 파일, 템플릿)이 잘못됐다. CLI 는 종료코드 2로 보고한다."""


def load_vars(plugin_root, repo):
    vp = pathlib.Path(repo) / VARS_PATH
    if not vp.exists():
        raise RolesError("변수 파일이 없습니다: %s — 먼저 /relay:init 으로 생성하세요." % vp)
    try:
        v = json.loads(vp.read_text(encoding="utf-8"))
    except ValueError as e:
        raise RolesError("변수 파일 JSON 오류: %s (%s)" % (vp, e))
    bad = [k for k in REQUIRED_KEYS if not str(v.get(k, "")).strip()]
    if bad:
        raise RolesError("필수 키가 없거나 비어 있습니다: %s (%s)" % (", ".join(bad), vp))
    pj = json.loads((pathlib.Path(plugin_root) / ".claude-plugin/plugin.json").read_text(encoding="utf-8"))
    v["version"] = pj["version"]
    return v


def _line(s):
    return s if not s or s.endswith("\n") else s + "\n"


def render(template, v):
    sub = {
        "VERSION": v["version"],
        "RULES_DOC": v.get("rules_doc", ""),
        "DEP_RULE": v.get("dep_rule", ""),
        "GATE_CMD_PROSE": v.get("gate_cmd_prose", ""),
        "GATE_CMD_RAW": v.get("gate_cmd_raw", ""),
        "GATE_PREP": _line(v.get("gate_prep", "")),
        "ASK_EXTRA": _line(v.get("ask_extra", "")),
        "REVIEW_FOCUS": v.get("review_focus", ""),
        "DEFAULT_BRANCH": v.get("default_branch", "main"),
    }
    out = template
    for k, val in sub.items():
        out = out.replace("{{%s}}" % k, val)
    left = sorted(set(PLACEHOLDER_RE.findall(out)))
    if left:
        raise RolesError("치환되지 않은 자리표시자: %s — .ai/relay-roles.json 에 키를 추가하거나 템플릿을 고치세요" % left)
    return out


def gitignore_text(old, logs):
    """old(.gitignore 내용, 개행은 LF 로 정규화된 것)에 relay 블록을 넣거나 갈아 끼운 결과."""
    body = "\n".join([
        BEGIN,
        "# 게이트는 종료코드로 판정하므로 출력을 파일로 받는다. 그 산출물이 워크트리에",
        "# 남으면 리뷰에서 SPEC_VIOLATION 으로 잡힌다 (synapse T-004 실측).",
    ] + list(logs) + [END])
    if BEGIN in old and END in old:
        pre, rest = old.split(BEGIN, 1)
        _, post = rest.split(END, 1)
        return pre + body + post
    return (old.rstrip("\n") + "\n\n" if old.strip() else "") + body + "\n"


def strip_stamp(text):
    """첫 줄이 생성 스탬프면 떼어낸다. 버전만 다른 것을 드리프트로 오인하지 않기 위해서다."""
    first, _sep, rest = text.partition("\n")
    if first.startswith(STAMP_PREFIX) and first.rstrip().endswith("-->"):
        return rest
    return text


def read_normalized(path):
    """(LF 정규화된 내용, 원래 개행) — 없으면 (None, None). 비교는 항상 LF 로 한다."""
    if not path.exists():
        return None, None
    raw = path.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), newline


def write_with_newline(path, text, newline):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.replace("\n", newline or "\n").encode("utf-8"))


class Target(object):
    def __init__(self, path, kind, cur, new, newline):
        self.path, self.kind, self.cur, self.new, self.newline = path, kind, cur, new, newline

    @property
    def state(self):
        if self.cur == self.new:
            return "same"
        if self.cur is None:
            return "create"
        if strip_stamp(self.cur) == strip_stamp(self.new):
            return "stamp"
        return "drift"

    @property
    def conflicts(self):
        # 손으로 고쳤을 수 있는 역할 파일만 force 없이 덮지 않는다
        return self.kind == "role" and self.state == "drift"


def plan(plugin_root, repo):
    plugin_root, repo = pathlib.Path(plugin_root), pathlib.Path(repo)
    v = load_vars(plugin_root, repo)
    targets = []
    for name in ROLE_NAMES:
        tmpl = (plugin_root / "templates" / (name + ".md.tmpl")).read_text(encoding="utf-8")
        path = repo / ".ai" / "roles" / (name + ".md")
        cur, nl = read_normalized(path)
        targets.append(Target(path, "role", cur, render(tmpl, v), nl))
    gp = repo / ".gitignore"
    cur, nl = read_normalized(gp)
    targets.append(Target(gp, "gitignore", cur, gitignore_text(cur or "", v.get("gate_logs", ["gate.log"])), nl))
    return v["version"], targets


def _diff(t, version, limit=40):
    d = difflib.unified_diff((t.cur or "").splitlines(), t.new.splitlines(),
                             "현재", "템플릿 v%s" % version, lineterm="", n=1)
    return ["  " + line for line in list(d)[:limit]]


def run(plugin_root, repo, mode=None):
    """(종료코드, 출력 줄 목록). 입력 오류는 RolesError 로 올린다."""
    version, targets = plan(plugin_root, repo)
    out = []
    changed = [t for t in targets if t.state != "same"]
    real = [t for t in changed if t.state != "stamp"]

    if mode == "check":
        if not real:
            if changed:
                out.append("OK  내용 동일. 스탬프만 낡음 (%d개 파일) — 필요하면 --force 로 갱신" % len(changed))
            else:
                out.append("OK  드리프트 없음 (relay-roles v%s)" % version)
            return 0, out
        for t in real:
            out.append("")
            out.append("DRIFT %s" % t.path)
            out.extend(_diff(t, version))
        out.append("")
        out.append("드리프트 %d개 파일. 템플릿이 옳으면 --force, 현재가 옳으면 템플릿을 고치세요." % len(real))
        return 1, out

    if not changed:
        out.append("변경 없음 (relay-roles v%s)" % version)
        return 0, out

    conflicts = [t for t in targets if t.conflicts]
    if conflicts and mode != "force":
        out.append("이미 존재하고 내용이 다릅니다 (아무것도 쓰지 않았습니다):")
        out.extend("  %s" % t.path for t in conflicts)
        out.append("--check 로 차이를 보거나 --force 로 덮어쓰세요.")
        return 2, out

    for t in changed:
        write_with_newline(t.path, t.new, t.newline)
        out.append("%s %s" % ("stamp" if t.state == "stamp" else "wrote", t.path))
    out.append("relay-roles v%s 적용" % version)
    return 0, out
