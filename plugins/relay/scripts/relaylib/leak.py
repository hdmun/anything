# -*- coding: utf-8 -*-
"""원격에 내보내기 전 gitleaks 유출 검사 — ADR 0001 (결정기).

진행자 세션이 git push·gh pr create·gh issue comment 로 내보내기 직전에 검사한다.
"""
import datetime
import json
import pathlib
import re
import tempfile

try:
    import tomllib
except ImportError:
    import tomli as tomllib

DEFAULT_CONFIG = pathlib.Path(__file__).with_name("leak_default.toml")
USER_RULES = pathlib.Path.home() / ".relay" / "leak-rules.toml"
REPO_ALLOW = ".ai/leak-allow.toml"
ALLOWLIST_FILES = (".gitleaksignore", REPO_ALLOW)
LOG_DIR = ".ai/leak"
LEAK_EXIT = 99
LEAK_NOTICE = "relay 멈춤 — 유출 검사에 걸려 내보내지 않았다. 자세한 결과는 이슈 워크트리 {worktree} 의 .ai/leak/ 로그에 있다."


class LeakError(Exception):
    """입력 오류(설정 파일 문법·키, gitleaks 없음·실행 실패). CLI 는 종료코드 2."""


def _last_nonempty_line(text):
    lines = [line.strip() for line in (text or "").splitlines() if line.strip()]
    return lines[-1] if lines else ""


def _unpack_run(res):
    if isinstance(res, tuple) and len(res) == 3:
        return res[0], res[1], res[2]
    rc, stdout = res[0], res[1]
    stderr = getattr(res, "stderr", "")
    return rc, stdout, stderr


def _strip_title(text):
    return re.sub(
        r'^\s*title\s*=\s*(?:"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\'|"[^"\\]*(?:\\.[^"\\]*)*"|\'[^\']*\'|[^\n\r#]*)(?:#[^\n\r]*)?(?:\r?\n|$)',
        '',
        text,
        flags=re.MULTILINE
    )


def build_config(default_text, user_text, repo_allow_text):
    """세 TOML 텍스트 → gitleaks 설정 TOML 텍스트. user_text·repo_allow_text 는 None 일 수 있다."""
    try:
        tomllib.loads(default_text)
    except Exception as e:
        raise LeakError(f"기본 설정 TOML 파싱 실패: {e}")

    user_part = ""
    if user_text is not None and user_text.strip():
        try:
            u = tomllib.loads(user_text)
        except Exception as e:
            raise LeakError(f"사용자 설정 파일 구문 오류: {e}")
        for k in u:
            if k not in ("title", "rules", "allowlists"):
                raise LeakError(f"사용자 설정 파일에 허용되지 않은 최상위 키: {k}")
        user_part = _strip_title(user_text).strip()

    repo_part = ""
    if repo_allow_text is not None and repo_allow_text.strip():
        try:
            r = tomllib.loads(repo_allow_text)
        except Exception as e:
            raise LeakError(f"저장소 허용 목록 구문 오류: {e}")
        for k in r:
            if k not in ("allowlists",):
                raise LeakError(f"저장소 허용 목록에 허용되지 않은 최상위 키: {k}")
        repo_part = repo_allow_text.strip()

    combined = default_text.rstrip()
    if user_part:
        combined += "\n\n" + user_part
    if repo_part:
        combined += "\n\n" + repo_part
    combined += "\n"

    try:
        tomllib.loads(combined)
    except Exception as e:
        raise LeakError(f"합친 설정 TOML 파싱 실패: {e}")

    return combined


def scan_text(text, config_path, run):
    """글 하나 → [{"rule": id, "line": n}]. run(argv, stdin=...) -> (rc, stdout)."""
    argv = [
        "gitleaks", "stdin",
        "--config", str(config_path),
        "--redact",
        "--ignore-gitleaks-allow",
        "--no-banner",
        "--exit-code", str(LEAK_EXIT),
        "--report-format", "json",
        "--report-path", "-"
    ]
    try:
        res = run(argv, stdin=text)
    except TypeError:
        res = run(argv)
    rc, stdout, _ = _unpack_run(res)
    if rc == 0:
        return []
    if rc == LEAK_EXIT:
        try:
            data = json.loads(stdout) if stdout.strip() else []
        except Exception as e:
            raise LeakError(f"gitleaks 출력 JSON 파싱 실패: {e}")
        return [{"rule": it["RuleID"], "line": it.get("StartLine", 1)} for it in data]
    if rc == 127:
        raise LeakError("gitleaks 를 찾을 수 없다")
    raise LeakError(f"gitleaks 실행 실패 (종료코드 {rc})")


def scan_range(worktree, base, config_path, run, git):
    """base..HEAD 의 추가된 줄과 커밋 메시지 → [{"rule", "file", "line"}]. git(worktree, *args) -> stdout."""
    out = git(worktree, "log", "--format=%H", f"{base}..HEAD")
    commits = [c.strip() for c in (out or "").splitlines() if c.strip()]
    if not commits:
        return []

    argv = [
        "gitleaks", "git", str(worktree),
        "--log-opts", f"{base}..HEAD",
        "--config", str(config_path),
        "--redact",
        "--ignore-gitleaks-allow",
        "--no-banner",
        "--exit-code", str(LEAK_EXIT),
        "--report-format", "json",
        "--report-path", "-"
    ]
    res = run(argv)
    rc, stdout, _ = _unpack_run(res)
    findings = []
    if rc == LEAK_EXIT:
        try:
            data = json.loads(stdout) if stdout.strip() else []
        except Exception as e:
            raise LeakError(f"gitleaks 출력 JSON 파싱 실패: {e}")
        for it in data:
            findings.append({"rule": it["RuleID"], "file": it.get("File", ""), "line": it.get("StartLine", 1)})
    elif rc == 127:
        raise LeakError("gitleaks 를 찾을 수 없다")
    elif rc != 0:
        raise LeakError(f"gitleaks 실행 실패 (종료코드 {rc})")

    for sha in commits:
        msg = git(worktree, "log", "-1", "--format=%B", sha)
        short_sha = sha[:7] if len(sha) >= 7 else sha
        msg_findings = scan_text(msg, config_path, run)
        for mf in msg_findings:
            findings.append({"rule": mf["rule"], "file": f"커밋 메시지 {short_sha}", "line": mf["line"]})

    return findings


def changed_allowlists(worktree, base, git):
    """base...HEAD 에서 바뀐 ALLOWLIST_FILES → [경로]."""
    out = git(worktree, "diff", "--name-only", f"{base}...HEAD")
    changed = {line.strip().replace("\\", "/") for line in (out or "").splitlines() if line.strip()}
    return [f for f in ALLOWLIST_FILES if f in changed]


def write_log(worktree, op, findings):
    """findings 를 <worktree>/.ai/leak/<UTC 시각>-<op>.json 에 쓰고 워크트리 기준 경로를 돌려준다."""
    leak_dir = pathlib.Path(worktree) / LOG_DIR
    leak_dir.mkdir(parents=True, exist_ok=True)
    gitignore = leak_dir / ".gitignore"
    if not gitignore.exists():
        gitignore.write_text("*\n", encoding="utf-8")
    ts = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    filename = f"{ts}-{op}.json"
    target = leak_dir / filename
    target.write_text(json.dumps({"op": op, "findings": findings}, ensure_ascii=False, indent=2), encoding="utf-8")
    return f"{LOG_DIR}/{filename}"


def _prepare_config(worktree, user_rules_path=None, default_config_path=None):
    def_path = default_config_path or DEFAULT_CONFIG
    if not def_path.is_file():
        raise LeakError(f"기본 설정 파일이 없다: {def_path}")
    default_text = def_path.read_text(encoding="utf-8")

    user_rules = user_rules_path or USER_RULES
    if not user_rules.is_file():
        raise LeakError(f"사용자 유출 규칙 파일이 없다: {user_rules}")
    user_text = user_rules.read_text(encoding="utf-8")

    repo_allow_path = pathlib.Path(worktree) / REPO_ALLOW
    repo_allow_text = repo_allow_path.read_text(encoding="utf-8") if repo_allow_path.is_file() else None

    return build_config(default_text, user_text, repo_allow_text)


def push(worktree, base="origin/main", force_with_lease=False, run=None, git=None,
         user_rules_path=None, default_config_path=None):
    """publish push 결정기. run·git 주입."""
    if git is None or run is None:
        raise LeakError("run 과 git 은 필수다")

    changed = changed_allowlists(worktree, base, git)
    if changed:
        return {"action": "stop", "reason": "allowlist_changed", "files": changed}

    cfg_text = _prepare_config(worktree, user_rules_path=user_rules_path, default_config_path=default_config_path)
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".toml", encoding="utf-8") as tmp:
        tmp.write(cfg_text)
        cfg_path = pathlib.Path(tmp.name)
    try:
        findings = scan_range(worktree, base, cfg_path, run, git)
    finally:
        try:
            cfg_path.unlink(missing_ok=True)
        except OSError:
            pass

    if findings:
        log_path = write_log(worktree, "push", findings)
        return {"action": "stop", "reason": "leak", "findings": findings, "log": log_path}

    if force_with_lease:
        cmd = ["git", "-C", str(worktree), "push", "--force-with-lease", "origin", "HEAD"]
    else:
        cmd = ["git", "-C", str(worktree), "push", "-u", "origin", "HEAD"]
    res = run(cmd)
    rc, stdout, stderr = _unpack_run(res)
    if rc != 0:
        detail = _last_nonempty_line(stderr) or _last_nonempty_line(stdout)
        return {"action": "stop", "reason": "push_failed", "detail": detail}

    branch = git(worktree, "branch", "--show-current").strip()
    return {"action": "pushed", "branch": branch, "range": f"{base}..HEAD"}


def pr(worktree, title, body_file, base="main", run=None, git=None,
       user_rules_path=None, default_config_path=None):
    """publish pr 결정기. run·git 주입."""
    if git is None or run is None:
        raise LeakError("run 과 git 은 필수다")

    branch = git(worktree, "branch", "--show-current").strip()
    res = run(["gh", "pr", "list", "--head", branch, "--state", "open", "--json", "url"], cwd=str(worktree))
    rc, stdout, stderr = _unpack_run(res)
    if rc == 0 and stdout.strip():
        try:
            items = json.loads(stdout)
        except Exception:
            items = []
        if items and isinstance(items, list) and items[0].get("url"):
            return {"action": "exists", "pr": items[0]["url"]}

    bp = pathlib.Path(body_file)
    if not bp.is_file() and (pathlib.Path(worktree) / body_file).is_file():
        bp = pathlib.Path(worktree) / body_file
    if not bp.is_file():
        raise LeakError(f"본문 파일이 없다: {body_file}")
    body_text = bp.read_text(encoding="utf-8")
    full_text = f"{title}\n{body_text}"

    cfg_text = _prepare_config(worktree, user_rules_path=user_rules_path, default_config_path=default_config_path)
    with tempfile.NamedTemporaryFile("w", delete=False, suffix=".toml", encoding="utf-8") as tmp:
        tmp.write(cfg_text)
        cfg_path = pathlib.Path(tmp.name)
    try:
        raw_findings = scan_text(full_text, cfg_path, run)
    finally:
        try:
            cfg_path.unlink(missing_ok=True)
        except OSError:
            pass

    if raw_findings:
        findings = [{"rule": f["rule"], "file": "pr", "line": f["line"]} for f in raw_findings]
        log_path = write_log(worktree, "pr", findings)
        return {"action": "stop", "reason": "leak", "findings": findings, "log": log_path}

    cmd = ["gh", "pr", "create", "--head", branch, "--base", base, "--title", title, "--body-file", str(bp)]
    res = run(cmd, cwd=str(worktree))
    rc, stdout, stderr = _unpack_run(res)
    if rc != 0:
        detail = _last_nonempty_line(stderr) or _last_nonempty_line(stdout)
        return {"action": "stop", "reason": "gh_failed", "detail": detail}

    pr_url = _last_nonempty_line(stdout)
    return {"action": "created", "pr": pr_url}


def comment(worktree, issue_url, body_file=None, leak_notice=False, run=None, git=None,
            user_rules_path=None, default_config_path=None):
    """publish comment 결정기. run·git 주입."""
    if git is None or run is None:
        raise LeakError("run 과 git 은 필수다")
    if bool(body_file) == bool(leak_notice):
        raise LeakError("--body-file 과 --leak-notice 중 하나만 지정해야 한다")

    created_temp = False
    if leak_notice:
        wt_name = pathlib.Path(worktree).name
        text = LEAK_NOTICE.format(worktree=wt_name)
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".md", encoding="utf-8") as tmp:
            tmp.write(text)
            body_path = pathlib.Path(tmp.name)
        created_temp = True
    else:
        bp = pathlib.Path(body_file)
        if not bp.is_file() and (pathlib.Path(worktree) / body_file).is_file():
            bp = pathlib.Path(worktree) / body_file
        if not bp.is_file():
            raise LeakError(f"본문 파일이 없다: {body_file}")
        body_path = bp
        text = body_path.read_text(encoding="utf-8")

    try:
        cfg_text = _prepare_config(worktree, user_rules_path=user_rules_path, default_config_path=default_config_path)
        with tempfile.NamedTemporaryFile("w", delete=False, suffix=".toml", encoding="utf-8") as tmp:
            tmp.write(cfg_text)
            cfg_path = pathlib.Path(tmp.name)
        try:
            raw_findings = scan_text(text, cfg_path, run)
        finally:
            try:
                cfg_path.unlink(missing_ok=True)
            except OSError:
                pass

        if raw_findings:
            findings = [{"rule": f["rule"], "file": "comment", "line": f["line"]} for f in raw_findings]
            log_path = write_log(worktree, "comment", findings)
            return {"action": "stop", "reason": "leak", "findings": findings, "log": log_path}

        cmd = ["gh", "issue", "comment", issue_url, "--body-file", str(body_path)]
        res = run(cmd, cwd=str(worktree))
        rc, stdout, stderr = _unpack_run(res)
        if rc != 0:
            detail = _last_nonempty_line(stderr) or _last_nonempty_line(stdout)
            return {"action": "stop", "reason": "gh_failed", "detail": detail}

        comment_url = _last_nonempty_line(stdout)
        return {"action": "posted", "url": comment_url}
    finally:
        if created_temp:
            try:
                body_path.unlink(missing_ok=True)
            except OSError:
                pass


publish_push = push
publish_pr = pr
publish_comment = comment
