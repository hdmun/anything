#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""relay 단일 진입점.

  python relay_cli.py roles --plugin-root <dir> [--repo <dir>] [--check | --force]
  python relay_cli.py trust add|remove <worktree> [--settings <file>]
  python relay_cli.py trust prune [--root <dir>] [--settings <file>] [--apply]
  python relay_cli.py diff-guard --worktree <dir> --base <sha>          (검사기)
  python relay_cli.py validate-review <I-<n>.rN.json>                   (검사기)
  python relay_cli.py review-branch --task I-<n> --worktree <dir> --base <sha> [--reviews <dir>]   (결정기)
  python relay_cli.py snapshot --issue <URL|path> --worktree <dir> --slug <slug>   (spec 스냅숏을 쓰고 JSON 한 줄)
  python relay_cli.py handoff-check --issue <URL|path> [--json]        (검사기 — 기동 전 검사: 태스크 수·필수 절·작성자)
  python relay_cli.py resume --worktree <dir> --tasks I-<a>,I-<b> [--base-branch main]   (결정기 — 재개: 다음 태스크)
  python relay_cli.py judgment validate <판정.json> [--reason spec_violation|repeated_finding|question]   (검사기)
  python relay_cli.py commit-guard --worktree <dir> --base <sha>        (검사기)
  python relay_cli.py model designer|coordinator|implementer|reviewer|judge [--repo <dir>] [--user-config <file>] [--config <codex toml>]   (결정기)
  python relay_cli.py models [--repo <dir>] [--user-config <file>]      (결정기 — 역할 전부 한눈에)
  python relay_cli.py models-init [--repo <dir> | --user] [--<역할>-model M] [--<역할>-effort E] ...
                                  [--force] [--print] [--no-verify]   (설정 파일 생성, 역할: designer|coordinator|implementer|reviewer|judge)
  python relay_cli.py doctor [--fix] [--json]                           (검사기 — 머신 점검)
  python relay_cli.py warmup agy                                        (결정기 — agy 업데이트를 Task 밖에서)
  python relay_cli.py smoke --dir <orca worktree> [--agent antigravity|codex|all]   (검사기 — worker-start 리허설, 수동)
                            [--repeat N] [--run <id>] [--model M] [--effort E]

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

from relaylib import doctor, handoff, issue, judgment, models, orca, resume, review, roles, smoke, trust


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
    return _emit(review.decide(reviews, a.task, _impl_rounds(a.worktree, a.base), _reports_since(a.worktree, a.base, reviews)))


def _reports_since(worktree, base, reviews):
    """base..HEAD 에서 생긴 리포트 이름 — 재개한 태스크는 라운드를 처음부터 센다(ADR 0010).

    리포트는 커밋하기 전에 분기하므로 아직 추적되지 않은 파일도 센다.
    """
    rel = pathlib.Path(reviews)
    try:
        rel = rel.resolve().relative_to(pathlib.Path(worktree).resolve())
    except ValueError:
        return None          # 워크트리 밖 디렉터리(테스트·특수용)는 모두 센다
    spec = rel.as_posix()
    names = _git(worktree, "diff", "--name-only", "--diff-filter=A", base, "HEAD", "--", spec).split()
    names += _git(worktree, "ls-files", "--others", "--exclude-standard", "--", spec).split()
    return {pathlib.PurePosixPath(n).name for n in names}


def cmd_resume(a):
    tasks = [t.strip() for t in a.tasks.split(",") if t.strip()]
    if not tasks:
        raise InputError("--tasks 가 비었다")
    out = _git(a.worktree, "log", "--format=%(trailers:key=" + resume.TRAILER + ",valueonly)", "%s..HEAD" % a.base_branch)
    return _emit(resume.decide(tasks, resume.done_tasks(out.splitlines())))


ATTRIBUTION_KEYS = ("Implemented-by", "Reviewed-by", "Judged-by")


def cmd_judgment(a):
    errs = judgment.check_file(a.path, a.reason)
    for e in errs:
        print(e, file=sys.stderr)
    return 1 if errs else 0


def cmd_snapshot(a):
    return _emit(issue.snapshot(a.issue, a.worktree, a.slug, _run))


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


def _models_cfg(a):
    try:
        return models.load_all(repo=a.repo, user_path=a.user_config)
    except models.ModelsError as e:
        raise InputError(str(e))


def _agy_models_text():
    rc, out = _run(["agy", "models"], timeout=60)
    return out if rc == 0 else None


def _codex_models_text():
    p = pathlib.Path.home() / ".codex" / "models_cache.json"
    return p.read_text(encoding="utf-8") if p.is_file() else None


def _decide_model(role, cfg, codex_config=None):
    if role == "reviewer":
        path = pathlib.Path(codex_config) if codex_config else pathlib.Path.home() / ".codex" / "config.toml"
        return orca.reviewer_model(path.read_text(encoding="utf-8"), cfg)
    if role == "implementer":
        return orca.implementer_model(cfg, _agy_models_text())
    if role == "coordinator":
        return orca.coordinator_model(cfg)
    if role == "judge":
        return orca.judge_model(cfg)
    return orca.session_model(role, cfg)


def cmd_model(a):
    cfg, _used = _models_cfg(a)
    return _emit(_decide_model(a.role, cfg, a.config))


def cmd_models_init(a):
    """역할별 model/effort 를 설정 파일로 만든다. 저장소(.ai/relay-models.json) 또는 사용자(~/.relay/models.json)."""
    cfg = models.build({role: {f: getattr(a, "%s_%s" % (role, f)) for f in models.FIELDS} for role in models.ROLES})
    for role in cfg:
        for f, v in cfg[role].items():
            models.check_value(role, f, v, "models-init")
    target = pathlib.Path(a.output) if a.output else models.USER_PATH if a.user else pathlib.Path(a.repo) / models.REPO_REL
    notes = []
    if not a.no_verify:
        impl = cfg.get("implementer")
        if impl:
            text = _agy_models_text()
            if text is None:
                notes.append("WARN agy models 를 실행하지 못해 구현자 값을 대조하지 못했다")
            else:
                status, detail, fix = models.check_agy(impl.get("model"), impl.get("effort"), text)
                if status == "fail":
                    raise InputError("%s — %s" % (detail, fix))
                if status == "warn":
                    notes.append("WARN " + detail)
        rev = cfg.get("reviewer")
        if rev and rev.get("model"):
            text = _codex_models_text()
            status, detail, fix = models.check_codex(rev["model"], rev.get("effort") or models.DEFAULT_EFFORT["reviewer"], text or "")
            if status == "fail":
                raise InputError("%s — %s" % (detail, fix))
            if status == "warn":
                notes.append("WARN " + detail)
    if target.exists() and not a.force:
        raise InputError("이미 있다: %s (--force 로 덮어쓰거나 --print 로 내용만 본다)" % target)
    text = models.render(cfg)
    if a.print:
        print(text, end="")
        return 0
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(text.encode("utf-8"))   # LF 로 쓴다 — 저장소에 커밋하는 파일
    print("wrote %s" % target)
    for n in notes:
        print(n)
    if not a.user and not a.output:
        print("저장소 설정이다 — 팀과 공유하려면 git add %s" % models.REPO_REL)
    return 0


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


ORCA_SKILLS_DIR = pathlib.Path.home() / ".agents" / "skills"


def _orca_skills_installed():
    return {name: (ORCA_SKILLS_DIR / name / "SKILL.md").is_file() for name in doctor.ORCA_SKILLS}


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
        "codex_models": _codex_models_text(),
        "codex_config": codex_cfg.read_text(encoding="utf-8") if codex_cfg.exists() else None,
        "versions": {k: _cli_version(k) for k in doctor.AGENTS},
        "verified": _verified(),
        "agy_settings": settings,
        "trust_root": str(trust.DEFAULT_ROOT),
        "exists": lambda p: pathlib.Path(p).is_dir(),
        "plugin_version": _plugin_version(),
        "installed_versions": _installed_versions(),
        "orca_skills": _orca_skills_installed(),
    }
    checks = doctor.evaluate(facts)
    if a.fix and settings is not None:
        dead = trust.prune(settings, str(trust.DEFAULT_ROOT))
        if dead:
            trust.save(agy, settings)
            checks.append({"name": "fix", "status": "ok", "detail": "trust 항목 %d개 정리: %s" % (len(dead), ", ".join(dead)), "fix": ""})
    _print_checks(checks, a.json)
    return doctor.exit_code(checks)


def _print_checks(checks, as_json):
    if as_json:
        print(json.dumps(checks, ensure_ascii=False))
        return
    mark = {"ok": "OK  ", "warn": "WARN", "fail": "FAIL"}
    for c in checks:
        print("%s %-16s %s" % (mark[c["status"]], c["name"], c["detail"]))
        if c["status"] != "ok" and c["fix"]:
            print("     %-16s → %s" % ("", c["fix"]))


def cmd_handoff_check(a):
    result = handoff.check(a.issue, _run)
    if a.json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        _print_checks(result["checks"], False)
        for t in result["tasks"]:
            print("task %s %s — %s" % (t["task"], t["url"], t["title"]))
    return handoff.exit_code(result["checks"])


def cmd_warmup(a):
    before = _cli_version("antigravity")
    rc, _ = _run(["agy", "update"], timeout=600) if before else (0, "")
    after = _cli_version("antigravity")
    return _emit(doctor.warmup_decide(before, rc, after, _verified()))


def _smoke_worker_launch(agent, cfg, a):
    """worker-start 경로의 (model, effort). --model·--effort 가 설정 파일보다 우선한다."""
    if agent == "antigravity":
        r = models.resolve("implementer", cfg)
        model, effort = r["model"], r["effort"]
    else:
        rev = _decide_model("reviewer", cfg)
        model, effort = (rev["model"], rev["effort"]) if rev["action"] == "launch" else (None, None)   # 미설정이면 codex 기본 모델
    return a.model or model, a.effort or effort


def cmd_smoke_worker(a, agents, cfg):
    wait_s = smoke.WORKER_WAIT_MS // 1000
    run = lambda argv: _run(argv, timeout=wait_s + 60)      # check --wait 보다 길게
    verified = _verified()
    ok = True
    for ag in agents:
        model, effort = _smoke_worker_launch(ag, cfg, a)
        r = smoke.run_workers(ag, a.dir.replace("\\", "/"), run, repeat=a.repeat, run_id=a.run,
                              version=_cli_version(ag), model=model, effort=effort)
        r["verified"] = r["version"] in verified.get(ag, [])
        a.run = r["run"]                                     # 두 에이전트를 같은 smoke Run 에 묶는다
        print(json.dumps(r, ensure_ascii=False))
        ok = ok and r["passed"]
    return 0 if ok else 1


def cmd_smoke(a):
    agents = ("antigravity", "codex") if a.agent == "all" else (a.agent,)
    if (a.model or a.effort) and len(agents) > 1:
        raise InputError("--model·--effort 는 --agent 하나와 함께 쓴다")
    cfg, _used = _models_cfg(a)
    return cmd_smoke_worker(a, agents, cfg)


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

    sn = sub.add_parser("snapshot", help="구현 이슈 본문 → .ai/specs/<ID>-<slug>.md (작성자 권한 확인)")
    sn.add_argument("--issue", required=True, help="GitHub 이슈 URL 또는 .scratch/<feature>/issues/<NN>-<slug>.md")
    sn.add_argument("--worktree", required=True)
    sn.add_argument("--slug", required=True, help="영문 소문자·숫자·하이픈")
    sn.set_defaults(func=cmd_snapshot)

    hc = sub.add_parser("handoff-check", help="기동 전 검사: 태스크 수 ≤5·템플릿 필수 절·작성자 권한")
    hc.add_argument("--issue", required=True, help="구현 이슈 URL 또는 .scratch/<feature>/issues/<NN>-<slug>.md")
    hc.add_argument("--json", action="store_true")
    hc.set_defaults(func=cmd_handoff_check)

    jg = sub.add_parser("judgment", help="판정 서브에이전트 출력 검증 (judgment-schema.json)")
    jg.add_argument("op", choices=("validate",))
    jg.add_argument("path")
    jg.add_argument("--reason", choices=tuple(judgment.DECISIONS), help="맡긴 사유 — 판정의 reason 과 같아야 한다")
    jg.set_defaults(func=cmd_judgment)

    rs = sub.add_parser("resume", help="Relay-Done 트레일러로 끝난 태스크를 보고 다음 태스크 (JSON 한 줄)")
    rs.add_argument("--worktree", required=True)
    rs.add_argument("--tasks", required=True, help="DAG 순서의 태스크 ID, 쉼표로")
    rs.add_argument("--base-branch", default="main")
    rs.set_defaults(func=cmd_resume)

    c = sub.add_parser("commit-guard", help="base..HEAD 에 귀속 트레일러 없는 커밋(워커 자체 커밋)이 없는지")
    c.add_argument("--worktree", required=True)
    c.add_argument("--base", required=True)
    c.set_defaults(func=cmd_commit_guard)

    m = sub.add_parser("model", help="역할별 모델·effort (설정 파일 → 실제 인자)")
    m.add_argument("role", choices=models.ROLES)
    m.add_argument("--config", help="reviewer 의 codex 설정. 기본: ~/.codex/config.toml")
    _add_models_args(m)
    m.set_defaults(func=cmd_model)

    ms = sub.add_parser("models", help="역할 전부의 model·effort 를 한 번에")
    _add_models_args(ms)
    ms.set_defaults(func=cmd_models)

    mi = sub.add_parser("models-init", help="역할별 model/effort 설정 파일 생성 (기본: <repo>/.ai/relay-models.json)")
    mi.add_argument("--repo", default=".", help="설정 파일을 만들 저장소. 기본: 현재 디렉터리")
    mi.add_argument("--user", action="store_true", help="저장소 대신 사용자 전역(~/.relay/models.json)에 만든다")
    mi.add_argument("--output", help="만들 파일 경로를 직접 지정 (테스트·특수용)")
    for role in models.ROLES:
        for f in models.FIELDS:
            mi.add_argument("--%s-%s" % (role, f))
    mi.add_argument("--force", action="store_true", help="이미 있어도 덮어쓴다")
    mi.add_argument("--print", action="store_true", help="쓰지 않고 내용만 출력한다")
    mi.add_argument("--no-verify", action="store_true", help="agy models·codex models_cache 대조를 건너뛴다")
    mi.set_defaults(func=cmd_models_init)

    dr = sub.add_parser("doctor", help="머신 점검: codex 설정·CLI 버전·trust·agy 권한")
    dr.add_argument("--fix", action="store_true", help="relay 워크트리 루트 아래 죽은 trust 항목만 정리")
    dr.add_argument("--json", action="store_true")
    _add_models_args(dr)
    dr.set_defaults(func=cmd_doctor)

    w = sub.add_parser("warmup", help="에이전트 CLI 업데이트를 Task 밖에서 끝낸다")
    w.add_argument("agent", choices=("agy",))
    w.set_defaults(func=cmd_warmup)

    sm = sub.add_parser("smoke", help="smoke 전용 Run 에서 worker-start --agent 기동·worker_done 확인 (수동)")
    sm.add_argument("--dir", required=True, help="Orca 에 등록된 워크트리 경로")
    sm.add_argument("--agent", default="all", choices=("antigravity", "codex", "all"))
    sm.add_argument("--repeat", type=int, default=1, help="반복 횟수 — 전부 통과해야 통과")
    sm.add_argument("--run", help="재사용할 smoke Run. 없으면 새로 만든다")
    sm.add_argument("--model", help="설정 파일 대신 쓸 model")
    sm.add_argument("--effort", help="설정 파일 대신 쓸 effort (--model 필요)")
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
    except (InputError, issue.IssueError, models.ModelsError, review.ReviewError, OSError, ValueError) as e:
        print(str(e), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
