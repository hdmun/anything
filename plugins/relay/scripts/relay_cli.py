#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""relay 단일 진입점.

  python relay_cli.py roles --plugin-root <dir> [--repo <dir>] [--check | --force]
  python relay_cli.py trust add|remove <worktree> [--settings <file>]
  python relay_cli.py trust prune [--root <dir>] [--settings <file>] [--apply]
  python relay_cli.py diff-guard --worktree <dir> --base <sha>          (검사기)
  python relay_cli.py validate-review <T-NNN.rN.json>                   (검사기)
  python relay_cli.py review-branch --task T-NNN --worktree <dir> --base <sha> [--reviews <dir>]   (결정기)
  python relay_cli.py commit-guard --worktree <dir> --base <sha>        (검사기)
  python relay_cli.py startup --response <file|-> [--prior-failures N]  (결정기)
  python relay_cli.py readiness --agent antigravity|codex --screen <file> [--agy-log <file>] --retries N [--recreated]   (결정기)
  python relay_cli.py liveness --worker <file> [--terminal <file>] --role implementer|reviewer [--now <ms>]   (결정기)
  python relay_cli.py model designer|coordinator|implementer|reviewer [--repo <dir>] [--user-config <file>] [--config <codex toml>]   (결정기)
  python relay_cli.py models [--repo <dir>] [--user-config <file>]      (결정기 — 4역할 한눈에)
  python relay_cli.py doctor [--fix] [--json]                           (검사기 — 머신 점검)
  python relay_cli.py warmup agy                                        (결정기 — agy 업데이트를 Task 밖에서)
  python relay_cli.py smoke --dir <trusted dir> [--agent antigravity|codex|all]   (검사기 — 실제 CLI 리허설, 수동)

규약 (docs/adr/0001):
  검사기 — 종료코드 0 통과 / 1 실패, 사유는 출력
  결정기 — stdout 에 JSON 한 줄, 종료코드 0
  입력 오류는 어느 쪽이든 종료코드 2, 사유는 stderr 한 줄
"""
import argparse
import json
import os
import pathlib
import subprocess
import sys

import time

from relaylib import doctor, models, orca, review, roles, smoke, trust


class InputError(Exception):
    pass


def _git(worktree, *args):
    r = subprocess.run(["git", "-C", str(worktree), *args], capture_output=True, text=True, encoding="utf-8")
    if r.returncode != 0:
        raise InputError("git %s 실패: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout


def _emit(decision):
    print(json.dumps(decision, ensure_ascii=False))
    return 0


def _utf8_stdio():
    # Windows 에서 출력을 파이프로 받으면 cp949 라 '—' 같은 문자에서 죽는다
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8")
        except (AttributeError, ValueError):
            pass


def cmd_roles(a):
    mode = "check" if a.check else ("force" if a.force else None)
    try:
        code, lines = roles.run(a.plugin_root, a.repo, mode)
    except roles.RolesError as e:
        print(str(e), file=sys.stderr)
        return 2
    for line in lines:
        print(line)
    return code


def cmd_trust(a):
    s = trust.load(a.settings)
    if a.op == "add":
        if trust.add(s, a.path):
            trust.save(a.settings, s)
            print("added: %s" % trust.normalize(a.path))
        else:
            print("already trusted: %s" % trust.normalize(a.path))
    elif a.op == "remove":
        if trust.remove(s, a.path):
            trust.save(a.settings, s)
            print("removed: %s" % trust.normalize(a.path))
        else:
            print("not present: %s" % trust.normalize(a.path))
    else:
        dead = trust.prune(s, a.root)
        for e in dead:
            print("dead: %s" % e)
        if dead and a.apply:
            trust.save(a.settings, s)
            print("pruned %d" % len(dead))
        elif dead:
            print("(dry-run) --apply 로 지운다")
        else:
            print("죽은 relay 항목 없음")
    return 0


def cmd_diff_guard(a):
    stat = _git(a.worktree, "diff", "--stat", "%s..HEAD" % a.base).strip()
    if not stat:
        print("리뷰할 변경 없음: %s..HEAD 가 비어 있다 — base 가 틀렸거나 구현 커밋이 없다" % a.base, file=sys.stderr)
        return 1
    print(stat.splitlines()[-1].strip())
    return 0


def cmd_validate_review(a):
    r, errs = review.load_report(a.path)
    for e in errs:
        print(e, file=sys.stderr)
    return 1 if errs else 0


def _impl_rounds(worktree, base):
    out = _git(worktree, "log", "--format=@@%(trailers:key=Implemented-by,valueonly,separator=|)", "%s..HEAD" % base)
    return sum(1 for chunk in out.split("@@") if chunk.strip())


def cmd_review_branch(a):
    reviews = a.reviews or str(pathlib.Path(a.worktree) / ".ai" / "reviews")
    return _emit(review.decide(reviews, a.task, _impl_rounds(a.worktree, a.base)))


ATTRIBUTION_KEYS = ("Implemented-by", "Reviewed-by")


def cmd_commit_guard(a):
    # 코디네이터가 만든 커밋만 있어야 한다 — 워커가 직접 커밋하면 귀속과 구현 라운드 수가 깨진다(T-004 dd95130)
    fmt = "@@%h%x09%s%x09%(trailers:only,unfold)"
    out = _git(a.worktree, "log", "--no-merges", "--format=" + fmt, "%s..HEAD" % a.base)
    bad = []
    for chunk in out.split("@@"):
        if not chunk.strip():
            continue
        sha, subject, trailers = (chunk.split("\t", 2) + ["", ""])[:3]
        if not any(line.split(":", 1)[0].strip() in ATTRIBUTION_KEYS for line in trailers.splitlines()):
            bad.append("%s %s" % (sha, subject.strip()))
    for b in bad:
        print("귀속 트레일러 없는 커밋: %s" % b, file=sys.stderr)
    return 1 if bad else 0


def _read_json_arg(path):
    text = sys.stdin.read() if path == "-" else pathlib.Path(path).read_text(encoding="utf-8")
    return json.loads(text)


def _unwrap_terminal(doc):
    # orca ... --json 출력({ok, result:{terminal:{...}}})과 맨 객체 둘 다 받는다
    if isinstance(doc, dict) and "result" in doc:
        doc = doc["result"]
    if isinstance(doc, dict) and "terminal" in doc:
        doc = doc["terminal"]
    return doc


def cmd_startup(a):
    return _emit(orca.startup(_read_json_arg(a.response), prior_failures=a.prior_failures))


def cmd_readiness(a):
    raw = pathlib.Path(a.screen).read_text(encoding="utf-8")
    try:
        t = _unwrap_terminal(json.loads(raw))
        screen = "\n".join(t["tail"]) if isinstance(t, dict) and "tail" in t else raw
    except ValueError:
        screen = raw
    if a.agent == "antigravity" and not a.agy_log:
        raise InputError("antigravity 는 --agy-log(최신 cli-*.log)가 필요하다 — 로그인 여부를 거기서 본다")
    if a.agent == "antigravity" and a.command is None:
        raise InputError("antigravity 는 --command(terminal create 에 준 --command 값)가 필요하다 — 단독 agy 면 기다려도 안 풀린다")
    log = pathlib.Path(a.agy_log).read_text(encoding="utf-8", errors="replace") if a.agy_log else None
    launch = None
    if a.agent == "antigravity":
        cfg, _used = _models_cfg(a)
        r = models.resolve("implementer", cfg)
        launch = orca.agy_launch_command(r["model"], r["effort"])
    return _emit(orca.readiness(screen, a.agent, a.retries, log=log, recreated=a.recreated, command=a.command,
                                launch_command=launch))


def cmd_liveness(a):
    worker = _read_json_arg(a.worker)
    if isinstance(worker, dict) and "result" in worker:
        r = worker["result"]
        ws = r.get("workers") if isinstance(r, dict) else r
        worker = ws[0] if isinstance(ws, list) and ws else r
    term = _unwrap_terminal(_read_json_arg(a.terminal)) if a.terminal else {}
    now = a.now if a.now is not None else int(time.time() * 1000)
    return _emit(orca.liveness(worker, term, a.role, now))


def _models_cfg(a):
    try:
        return models.load_all(repo=a.repo, user_path=a.user_config)
    except models.ModelsError as e:
        raise InputError(str(e))


def _agy_models_text():
    rc, out = _run(["agy", "models"], timeout=60)
    return out if rc == 0 else None


def _decide_model(role, cfg, codex_config=None):
    if role == "reviewer":
        path = pathlib.Path(codex_config) if codex_config else pathlib.Path.home() / ".codex" / "config.toml"
        return orca.reviewer_model(path.read_text(encoding="utf-8"), cfg)
    if role == "implementer":
        return orca.implementer_model(cfg, _agy_models_text())
    return orca.session_model(role, cfg)


def cmd_model(a):
    cfg, _used = _models_cfg(a)
    return _emit(_decide_model(a.role, cfg, a.config))


def cmd_models(a):
    cfg, used = _models_cfg(a)
    out = {"files": used}
    for role in models.ROLES:
        try:
            out[role] = _decide_model(role, cfg)
        except OSError as e:     # codex config.toml 이 없는 등 — 한 역할이 막아도 나머지는 보여 준다
            out[role] = {"action": "human", "reason": "unreadable", "detail": str(e)}
    return _emit(out)


AGY_LOG_DIR = pathlib.Path.home() / ".gemini" / "antigravity-cli" / "log"
CLI_BINARIES = {"codex": "codex", "antigravity": "agy", "orca": "orca"}


def _run(argv, timeout=120):
    """(rc, stdout). 실행 파일이 없으면 (127, '')."""
    try:
        r = subprocess.run(argv, capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=timeout, shell=(sys.platform == "win32"))
    except (OSError, subprocess.TimeoutExpired):
        return 127, ""
    return r.returncode, r.stdout


def _cli_version(agent):
    rc, out = _run([CLI_BINARIES[agent], "--version"], timeout=30)
    return doctor.parse_version(out) if rc == 0 else None


def _verified():
    return json.loads(doctor.VERIFIED_PATH.read_text(encoding="utf-8"))


def _newest_agy_log():
    logs = sorted(AGY_LOG_DIR.glob("cli-*.log"), key=lambda p: p.stat().st_mtime) if AGY_LOG_DIR.is_dir() else []
    return logs[-1].read_text(encoding="utf-8", errors="replace") if logs else ""


def _plugin_version():
    """이 스크립트가 들어 있는 플러그인 사본의 버전 — 세션이 실제로 읽고 있는 버전이다."""
    p = pathlib.Path(__file__).resolve().parents[1] / ".claude-plugin" / "plugin.json"
    return json.loads(p.read_text(encoding="utf-8")).get("version") if p.exists() else None


def _installed_versions():
    """이 세션의 설정 디렉터리(CLAUDE_CONFIG_DIR, 없으면 ~/.claude)에 설치 기록된 relay 버전들."""
    cfg = pathlib.Path(os.environ.get("CLAUDE_CONFIG_DIR") or pathlib.Path.home() / ".claude")
    p = cfg / "plugins" / "installed_plugins.json"
    if not p.exists():
        return []
    d = json.loads(p.read_text(encoding="utf-8"))
    entries = [e for k, v in (d.get("plugins") or {}).items() if k.startswith("relay@")
               for e in (v if isinstance(v, list) else [v])]
    return [e["version"] for e in entries if e.get("version")]


def cmd_doctor(a):
    codex_cfg = pathlib.Path.home() / ".codex" / "config.toml"
    agy = trust.DEFAULT_SETTINGS
    settings = trust.load(agy) if agy.exists() else None
    models_error, models_cfg, models_files = None, {}, []
    try:
        models_cfg, models_files = models.load_all(repo=a.repo, user_path=a.user_config)
    except models.ModelsError as e:
        models_error = str(e)
    facts = {
        "models_error": models_error, "models_cfg": models_cfg, "models_files": models_files,
        "agy_models": _agy_models_text() if models_files else None,
        "codex_config": codex_cfg.read_text(encoding="utf-8") if codex_cfg.exists() else None,
        "versions": {k: _cli_version(k) for k in doctor.AGENTS},
        "verified": _verified(),
        "agy_settings": settings,
        "trust_root": str(trust.DEFAULT_ROOT),
        "exists": lambda p: pathlib.Path(p).is_dir(),
        "plugin_version": _plugin_version(),
        "installed_versions": _installed_versions(),
    }
    checks = doctor.evaluate(facts)
    if a.fix and settings is not None:
        dead = trust.prune(settings, str(trust.DEFAULT_ROOT))
        if dead:
            trust.save(agy, settings)
            checks.append({"name": "fix", "status": "ok", "detail": "trust 항목 %d개 정리: %s" % (len(dead), ", ".join(dead)), "fix": ""})
    if a.json:
        print(json.dumps(checks, ensure_ascii=False))
    else:
        mark = {"ok": "OK  ", "warn": "WARN", "fail": "FAIL"}
        for c in checks:
            print("%s %-16s %s" % (mark[c["status"]], c["name"], c["detail"]))
            if c["status"] != "ok" and c["fix"]:
                print("     %-16s → %s" % ("", c["fix"]))
    return doctor.exit_code(checks)


def cmd_warmup(a):
    before = _cli_version("antigravity")
    rc, _ = _run(["agy", "update"], timeout=600) if before else (0, "")
    after = _cli_version("antigravity")
    return _emit(doctor.warmup_decide(before, rc, after, _verified()))


def cmd_smoke(a):
    agents = ("antigravity", "codex") if a.agent == "all" else (a.agent,)
    cfg, _used = _models_cfg(a)
    impl = models.resolve("implementer", cfg)
    cmds = {"antigravity": orca.agy_launch_command(impl["model"], impl["effort"])}   # 설정이 있으면 그 model·effort 로 리허설한다
    rev = _decide_model("reviewer", cfg)
    if rev["action"] == "launch":
        cmds["codex"] = orca.codex_launch_command(rev["model"], rev["effort"])
    results = [smoke.run_agent(ag, a.dir.replace("\\", "/"), lambda argv: _run(argv, timeout=180),
                               read_log=_newest_agy_log, version=_cli_version(ag), command=cmds.get(ag)) for ag in agents]
    verified = _verified()
    for r in results:
        r["verified"] = r["version"] in verified.get(r["agent"], [])
        print(json.dumps(r, ensure_ascii=False))
    return 0 if all(r["passed"] for r in results) else 1


def _add_models_args(p):
    p.add_argument("--repo", default=".", help="저장소별 설정(.ai/relay-models.json)을 찾을 저장소. 기본: 현재 디렉터리")
    p.add_argument("--user-config", help="사용자 전역 설정. 기본: ~/.relay/models.json")


def build_parser():
    ap = argparse.ArgumentParser(prog="relay_cli.py")
    sub = ap.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("roles", help="역할 파일 생성·드리프트 검증")
    r.add_argument("--plugin-root", required=True)
    r.add_argument("--repo", default=".")
    g = r.add_mutually_exclusive_group()
    g.add_argument("--check", action="store_true")
    g.add_argument("--force", action="store_true")
    r.set_defaults(func=cmd_roles)

    t = sub.add_parser("trust", help="agy trustedWorkspaces 추가·제거·정리")
    t.add_argument("op", choices=("add", "remove", "prune"))
    t.add_argument("path", nargs="?")
    t.add_argument("--settings", default=str(trust.DEFAULT_SETTINGS))
    t.add_argument("--root", default=str(trust.DEFAULT_ROOT), help="prune: relay 워크트리 루트")
    t.add_argument("--apply", action="store_true", help="prune: 실제로 지운다")
    t.set_defaults(func=cmd_trust)

    d = sub.add_parser("diff-guard", help="리뷰 전 base..HEAD 가 비어 있지 않은지")
    d.add_argument("--worktree", required=True)
    d.add_argument("--base", required=True)
    d.set_defaults(func=cmd_diff_guard)

    v = sub.add_parser("validate-review", help="리뷰 리포트 스키마 검증")
    v.add_argument("path")
    v.set_defaults(func=cmd_validate_review)

    b = sub.add_parser("review-branch", help="리뷰 결과 → 다음 행동 (JSON 한 줄)")
    b.add_argument("--task", required=True)
    b.add_argument("--worktree", required=True)
    b.add_argument("--base", required=True)
    b.add_argument("--reviews", help="기본: <worktree>/.ai/reviews")
    b.set_defaults(func=cmd_review_branch)

    c = sub.add_parser("commit-guard", help="base..HEAD 에 귀속 트레일러 없는 커밋(워커 자체 커밋)이 없는지")
    c.add_argument("--worktree", required=True)
    c.add_argument("--base", required=True)
    c.set_defaults(func=cmd_commit_guard)

    s = sub.add_parser("startup", help="worker-start 응답 → 다음 행동")
    s.add_argument("--response", required=True, help="worker-start --json 출력 파일, - 면 stdin")
    s.add_argument("--prior-failures", type=int, default=0, help="이 태스크 계열의 이전 기동 실패 수")
    s.set_defaults(func=cmd_startup)

    rd = sub.add_parser("readiness", help="tui-idle timeout 이후 다음 행동")
    rd.add_argument("--agent", required=True, choices=("antigravity", "codex"))
    rd.add_argument("--screen", required=True, help="terminal read --screen 출력(텍스트 또는 --json)")
    rd.add_argument("--agy-log", help="agy 최신 cli-*.log")
    rd.add_argument("--retries", type=int, required=True, help="이미 다시 건 tui-idle 횟수")
    rd.add_argument("--recreated", action="store_true", help="이미 한 번 재생성했다")
    rd.add_argument("--command", help="terminal create 에 준 --command 값 (antigravity 필수)")
    _add_models_args(rd)
    rd.set_defaults(func=cmd_readiness)

    lv = sub.add_parser("liveness", help="빈 대기 3회 뒤 무응답 판정")
    lv.add_argument("--worker", required=True, help="worker-list --json 출력(또는 그 항목) 파일, - 면 stdin")
    lv.add_argument("--terminal", help="terminal show --json 출력 파일")
    lv.add_argument("--role", required=True, choices=tuple(orca.STALL_MS))
    lv.add_argument("--now", type=int, help="epoch ms (테스트용)")
    lv.set_defaults(func=cmd_liveness)

    m = sub.add_parser("model", help="역할별 모델·effort (설정 파일 → 실제 인자)")
    m.add_argument("role", choices=models.ROLES)
    m.add_argument("--config", help="reviewer 의 codex 설정. 기본: ~/.codex/config.toml")
    _add_models_args(m)
    m.set_defaults(func=cmd_model)

    ms = sub.add_parser("models", help="4역할의 model·effort 를 한 번에")
    _add_models_args(ms)
    ms.set_defaults(func=cmd_models)

    dr = sub.add_parser("doctor", help="머신 점검: codex 설정·CLI 버전·trust·agy 권한")
    dr.add_argument("--fix", action="store_true", help="relay 워크트리 루트 아래 죽은 trust 항목만 정리")
    dr.add_argument("--json", action="store_true")
    _add_models_args(dr)
    dr.set_defaults(func=cmd_doctor)

    w = sub.add_parser("warmup", help="에이전트 CLI 업데이트를 Task 밖에서 끝낸다")
    w.add_argument("agent", choices=("agy",))
    w.set_defaults(func=cmd_warmup)

    sm = sub.add_parser("smoke", help="Task 없이 실제 기동·전달 확인 (수동)")
    sm.add_argument("--dir", required=True, help="agy trustedWorkspaces 에 등록된 디렉터리")
    sm.add_argument("--agent", default="all", choices=("antigravity", "codex", "all"))
    _add_models_args(sm)
    sm.set_defaults(func=cmd_smoke)
    return ap


def main(argv=None):
    _utf8_stdio()
    ap = build_parser()
    a = ap.parse_args(argv)
    if a.cmd == "trust" and a.op != "prune" and not a.path:
        ap.error("trust %s 에는 경로가 필요하다" % a.op)
    try:
        return a.func(a)
    except (InputError, review.ReviewError, OSError, ValueError) as e:
        print(str(e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
