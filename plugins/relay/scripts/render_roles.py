#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""하위 호환 진입점 — `relay_cli.py roles` 와 같다.

  python render_roles.py --plugin-root <dir> [--repo <dir>] [--check | --force]

기존 안내(commands/init.md, 저장소 README)가 이 경로를 부르므로 남겨 둔다.
"""
import sys

import relay_cli

if __name__ == "__main__":
    sys.exit(relay_cli.main(["roles"] + sys.argv[1:]))
