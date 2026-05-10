#!/usr/bin/env bash
#
# Smoke-test for examples/plain-html/build.sh.
#
# The plain-html example is the canonical "contract distilled" reference.
# It has no generator, so the entire build is the contract: read
# SITE_VERSION_KEY / SITE_BASE / DIST_DIR from env, copy src/ to
# $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/. This test runs build.sh in
# both layouts and asserts the output paths.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE="$REPO_ROOT/examples/plain-html"

[ -x "$EXAMPLE/build.sh" ] || { echo "FAIL: $EXAMPLE/build.sh not executable" >&2; exit 1; }

PASS=0
FAIL=0

assert_file() {
  if [ -f "$1" ]; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: missing $1" >&2
    FAIL=$((FAIL + 1))
  fi
}

# --- Scenario 1: no SITE_BASE -----------------------------------------------

sandbox="$(mktemp -d)"
# shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
trap "rm -rf $sandbox" EXIT

echo
echo "scenario: plain-html, no SITE_BASE"
(
  cd "$EXAMPLE"
  SITE_VERSION_KEY=next DIST_DIR="$sandbox/dist1" ./build.sh >/dev/null
)
assert_file "$sandbox/dist1/next/index.html"
assert_file "$sandbox/dist1/next/guide.html"
assert_file "$sandbox/dist1/next/versions.json"
# switcher.js is dropped in by the orchestrator (scripts/build-versions.sh
# copy_switcher), not by the example's own build.sh. The plain-html src/
# does not include one, so a standalone build correctly omits it; the
# multi-version test in test-build-versions.sh exercises the copy.

# --- Scenario 2: with SITE_BASE ---------------------------------------------

echo
echo "scenario: plain-html, with SITE_BASE"
(
  cd "$EXAMPLE"
  SITE_VERSION_KEY=0.9 SITE_BASE=docs DIST_DIR="$sandbox/dist2" ./build.sh >/dev/null
)
assert_file "$sandbox/dist2/docs/0.9/index.html"
assert_file "$sandbox/dist2/docs/0.9/guide.html"

echo
echo "results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
