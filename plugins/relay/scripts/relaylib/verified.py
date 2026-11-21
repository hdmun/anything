# -*- coding: utf-8 -*-
"""검증된 버전 기록 — 이 PC 에서 smoke 를 통과한 에이전트 CLI 버전.

기록은 사용자 파일 ~/.relay/verified.json 에 있다. relay_cli.py smoke 가 통과하면 자동으로 더한다.
doctor·warmup 은 이 기록과 현재 버전을 비교해 미검증이면 경고한다.
"""
import json
import pathlib

USER_PATH = pathlib.Path.home() / ".relay" / "verified.json"
AGENTS = ("codex", "antigravity", "orca")


class VerifiedError(Exception):
    """기록 파일이 깨졌다. 조용히 덮어쓰지 않는다."""


def load(path) -> dict:
    """{"codex": [...], "antigravity": [...], "orca": [...]} — 세 키가 항상 있다."""
    path = pathlib.Path(path)
    if not path.exists():
        return {k: [] for k in AGENTS}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (ValueError, UnicodeDecodeError) as e:
        raise VerifiedError("%s: JSON 오류 (%s)" % (path, e))
    if not isinstance(raw, dict):
        raise VerifiedError("%s: 최상위는 객체여야 한다" % path)
    out = {}
    for k in AGENTS:
        v = raw.get(k, [])
        if not isinstance(v, list) or not all(isinstance(x, str) for x in v):
            raise VerifiedError("%s: %s 는 문자열 리스트여야 한다 (받은 값: %r)" % (path, k, v))
        out[k] = list(v)
    return out


def record(path, versions: dict) -> dict:
    """versions = {"antigravity": "1.5.13", "orca": "1.4.265"} 처럼 기록할 것만. 갱신된 전체 내용을 돌려준다."""
    path = pathlib.Path(path)
    data = load(path)
    for agent, ver in versions.items():
        if agent not in data:
            raise VerifiedError("모르는 에이전트: %r" % agent)
        if ver not in data[agent]:
            data[agent].append(ver)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return data
