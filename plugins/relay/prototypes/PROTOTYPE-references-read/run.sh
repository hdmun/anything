#!/usr/bin/env bash
# PROTOTYPE: 변형마다 eval 을 돌린다. 결과는 out/<변형>/evals/results/
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
for v in "${@:-v0-monolith v1-pointer v2-imperative v3-entry-table}"; do for x in $v; do
  echo "== $x"; claude plugin eval "$here/out/$x" --trust-plugin --ablation none --no-publish -j 3 --runs 3 --threshold 0 --judge-model sonnet --json "$here/out/$x.json" 2>&1 | tail -15
done; done
