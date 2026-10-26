#!/bin/bash
# CI only: decide the suite and filters for this run, printed as GITHUB_OUTPUT lines.
# Order: manual-run inputs, then a .ci-request file in the commit (written by scripts/ci.sh), then "unit".
set -euo pipefail
suite="${INPUT_SUITE:-}"
filters="${INPUT_FILTERS:-}"
if [ -z "$suite" ] && [ -f .ci-request ]; then
  suite=$(sed -n 's/^suite=//p' .ci-request | head -1)
  filters=$(sed -n 's/^filters=//p' .ci-request | head -1)
fi
suite="${suite:-unit}"
case "$suite" in unit|build|ui|all|fresh-clone) ;; *) echo "Unknown suite: $suite" >&2; exit 1 ;; esac
# Filters may only contain test identifiers (letters, digits, _ / .), never shell syntax.
if [ -n "$filters" ] && ! printf '%s' "$filters" | grep -Eq '^[A-Za-z0-9_/. ]+$'; then
  echo "Bad filters: $filters" >&2
  exit 1
fi
echo "suite=$suite"
echo "filters=$filters"
