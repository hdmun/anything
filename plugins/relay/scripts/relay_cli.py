#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""relay 단일 진입점.

  python relay_cli.py roles --plugin-root <dir> [--repo <dir>] [--check | --force]
  python relay_cli.py trust add|remove <worktree> [--settings <file>]
  python relay_cli.py trust prune [--root <dir>] [--settings <file>] [--apply]
  python relay_cli.py diff-guard --worktree <dir> --base <sha>          (검사기)
  python relay_cli.py validate-review <T-NNN.rN.json>                   (검사기)
  python relay_cli.py review-branch --task T-NNN --worktree <dir> --base <sha> [--reviews <dir>]   (결정기)

규약 (docs/adr/0001):
  검사기 — 종료코드 0 통과 / 1 실패, 사유는 출력
  결정기 — stdout 에 JSON 한 줄, 종료코드 0
  입력 오류는 어느 쪽이든 종료코드 2, 사유는 stderr 한 줄
"""
import argparse
import json
import pathlib
import subprocess
import sys

from relaylib import review, roles, trust


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
