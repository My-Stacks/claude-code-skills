#!/usr/bin/env bash
# run.sh — full ai-router test suite (deterministic primitives + safety logic).
# Exit 0 iff everything passes. Hermetic: no network, no real GitHub (gh is
# stubbed in the bash suites). Safe to use as a self-check / CI gate.
#
#   bash tests/run.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fail=0

command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 3; }
command -v jq      >/dev/null 2>&1 || { echo "jq required" >&2; exit 3; }
command -v git     >/dev/null 2>&1 || { echo "git required" >&2; exit 3; }

echo "==== python primitives ===="
( cd "$HERE" && python3 -m unittest discover -s "$HERE" -p 'test_*.py' ) || fail=1

echo "==== bash safety suites ===="
for t in "$HERE"/test_*.sh; do
  echo "-- $(basename "$t") --"
  bash "$t" || fail=1
done

echo "========================================"
if [ "$fail" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "SOME TESTS FAILED"; fi
exit "$fail"
