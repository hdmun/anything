# -*- coding: utf-8 -*-
"""agy 의 trustedWorkspaces 관리.

등록하지 않으면 agy 가 "Do you trust the contents of this project?" 에서 멈춘다(SKILL (d)).
relay 가 추가한 항목은 성공 종료 때 지우고, 지우지 못하고 남은 죽은 항목은 prune 으로 정리한다.
경로 비교는 Windows 기준이라 대소문자를 무시한다.
"""
import json
import os
import pathlib

KEY = "trustedWorkspaces"
DEFAULT_SETTINGS = pathlib.Path.home() / ".gemini" / "antigravity-cli" / "settings.json"
DEFAULT_ROOT = pathlib.Path.home() / "orca" / "workspaces"


def normalize(path):
    # worktree create 는 C:/... 로 주지만 기존 항목은 백슬래시다
    p = str(path).replace("/", "\\")
    return p.rstrip("\\") if len(p) > 3 else p


def _key(path):
    return normalize(path).lower()


def add(settings, path):
    """추가했으면 True, 이미 있으면 False."""
    ws = settings.setdefault(KEY, [])
    if any(_key(e) == _key(path) for e in ws):
        return False
    ws.append(normalize(path))
    return True


def remove(settings, path):
    """지운 항목 수."""
    ws = settings.get(KEY, [])
    keep = [e for e in ws if _key(e) != _key(path)]
    n = len(ws) - len(keep)
    if n:
        settings[KEY] = keep
    return n


def _under(entry, root):
    e, r = _key(entry), _key(root)
    return e == r or e.startswith(r + "\\")


def prune(settings, root, exists=os.path.isdir):
    """root(relay 워크트리 루트) 아래에 있고 디렉터리가 사라진 항목만 지운다. 사용자 항목은 건드리지 않는다."""
    ws = settings.get(KEY, [])
    dead = [e for e in ws if _under(e, root) and not exists(e)]
    if dead:
        settings[KEY] = [e for e in ws if e not in dead]
    return dead


def load(path=DEFAULT_SETTINGS):
    return json.loads(pathlib.Path(path).read_text(encoding="utf-8"))


def save(path, settings):
    pathlib.Path(path).write_text(json.dumps(settings, ensure_ascii=False, indent=2), encoding="utf-8")
