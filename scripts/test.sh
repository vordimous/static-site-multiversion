#!/usr/bin/env bash
#
# Run all repo tests. Add new test scripts under test/ and they'll be picked up.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

shopt -s nullglob
tests=(test/test-*.sh)
shopt -u nullglob

if [ ${#tests[@]} -eq 0 ]; then
  echo "no tests found under test/" >&2
  exit 0
fi

failures=0
for t in "${tests[@]}"; do
  echo "==> $t"
  if ! bash "$t"; then
    failures=$((failures + 1))
  fi
  echo
done

if [ "$failures" -ne 0 ]; then
  echo "$failures test file(s) failed" >&2
  exit 1
fi

echo "all tests passed"
