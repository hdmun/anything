#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""relay 단일 진입점.

  python relay_cli.py roles --plugin-root <dir> [--repo <dir>] [--check | --force]

규약 (docs/adr/0001):
  검사기 — 종료코드 0 통과 / 1 실패, 사유는 출력
  결정기 — stdout 에 JSON 한 줄, 종료코드 0
  입력 오류는 어느 쪽이든 종료코드 2, 사유는 stderr 한 줄
"""
import argparse
import sys

from relaylib import roles


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
    return ap


def main(argv=None):
    _utf8_stdio()
    a = build_parser().parse_args(argv)
    return a.func(a)


if __name__ == "__main__":
    sys.exit(main())
