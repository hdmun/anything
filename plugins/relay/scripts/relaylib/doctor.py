# -*- coding: utf-8 -*-
"""머신 단위 점검(doctor)과 agy 예열 결정 — 진행 세션 (c)0 단계에서 돈다.

evaluate() 는 수집된 사실(facts)만 보고 판정한다. 수집과 --fix 쓰기는 relay_cli 가 한다.
"""
import copy
import pathlib
import re

from relaylib import orca, trust

VERIFIED_PATH = pathlib.Path(__file__).resolve().parents[2] / "skills" / "relay" / "references" / "verified-cli.json"
AGENTS = ("codex", "antigravity", "orca")
_VERSION_RE = re.compile(r"(\d+\.\d+\.\d+)")


def parse_version(text):
    """`codex-cli 0.159.3`, `1.2.16`, crashpad 잡음이 섞인 orca 출력에서 마지막 x.y.z."""
    found = _VERSION_RE.findall(text or "")
    return found[-1] if found else None


def _check(name, status, detail, fix=""):
    return {"name": name, "status": status, "detail": detail, "fix": fix}


def _codex(config_text):
    if config_text is None:
        return _check("codex", "fail", "~/.codex/config.toml 이 없다", "codex 를 한 번 실행해 설정 파일을 만든다")
    d = orca.reviewer_model(config_text)
    if d["action"] == "launch":
        return _check("codex", "ok", "리뷰어 모델: %s / %s (codex 기본 모델)" % (d["model"], d["effort"]))
    if d["reason"] == "codex_prereq_missing":
        return _check("codex", "fail", "사전 조건 누락: " + "; ".join(d["missing"]),
                      'config.toml 에 추가: check_for_update_on_startup = false / [tui] terminal_title = ["app-name", "activity", "project-name"]')
    return _check("codex", "fail", "config.toml 에 최상위 model 이 없다", 'model = "<리뷰어로 쓸 모델>"')


def _version(agent, version, verified):
    name = "version:" + agent
    if version is None:
        return _check(name, "fail", "%s 를 찾을 수 없다 (PATH)" % agent, "설치하거나 PATH 에 추가한다")
    if version in verified.get(agent, []):
        return _check(name, "ok", version)
    return _check(name, "warn", "%s 는 검증된 버전이 아니다 (검증: %s)" % (version, ", ".join(verified.get(agent, [])) or "없음"),
                  "relay_cli.py smoke 가 통과하면 references/verified-cli.json 에 사람이 추가한다")


def _trust(settings, root, exists):
    if settings is None:
        return _check("trust", "warn", "agy settings.json 이 없다", "agy 를 한 번 실행한다")
    dead = trust.prune(copy.deepcopy(settings), root, exists=exists)
    if not dead:
        return _check("trust", "ok", "죽은 relay 항목 없음 (%d개 등록)" % len(settings.get(trust.KEY, [])))
    return _check("trust", "warn", "삭제된 워크트리를 가리키는 항목 %d개: %s" % (len(dead), ", ".join(dead)),
                  "relay_cli.py doctor --fix (relay 워크트리 루트 아래만 지운다)")


def _agy_permissions(settings):
    allow = ((settings or {}).get("permissions") or {}).get("allow") or []
    risky = [p for p in allow if p in ("command(git commit)", "command(powershell)")]
    if not risky:
        return _check("agy-permissions", "ok", "구현자가 직접 커밋할 권한 없음")
    return _check("agy-permissions", "warn",
                  "agy 가 직접 커밋할 수 있다: %s — 귀속 트레일러 없는 커밋이 생긴다(T-004 dd95130)" % ", ".join(risky),
                  "~/.gemini/antigravity-cli/settings.json 의 permissions.allow 에서 command(git commit) 제거. "
                  "command(powershell) 이 남으면 우회 가능 — commit-guard 가 최종 방어선")


def evaluate(f):
    checks = [_codex(f.get("codex_config"))]
    for agent in AGENTS:
        checks.append(_version(agent, (f.get("versions") or {}).get(agent), f.get("verified") or {}))
    checks.append(_trust(f.get("agy_settings"), f.get("trust_root", str(trust.DEFAULT_ROOT)), f.get("exists")))
    checks.append(_agy_permissions(f.get("agy_settings")))
    return checks


def exit_code(checks):
    return 1 if any(c["status"] == "fail" for c in checks) else 0


def warmup_decide(before, update_rc, after, verified):
    """agy update 전후 → 다음 행동. 업데이트를 막지 않고 Task 밖에서 끝낸다 (CONTEXT.md 「예열」)."""
    if after is None:
        return {"action": "human", "reason": "agy_not_found"}
    if update_rc != 0:
        return {"action": "human", "reason": "update_failed", "version": after}
    return {"action": "ready", "version": after, "updated": before != after,
            "unverified": after not in verified.get("antigravity", [])}
