#!/usr/bin/env bash
#
# End-to-end test for scripts/build-versions.sh.
#
# Sets up a throwaway git repo with two tagged historical versions plus a HEAD,
# runs the orchestrator against it using test/fake-build.sh as the builder, and
# asserts the resulting dist/ tree contains one correct subdirectory per
# version. Also exercises the SITE_BASE path-prefix flow.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/build-versions.sh"
FAKE_BUILD="$REPO_ROOT/test/fake-build.sh"

[ -x "$SCRIPT" ]     || { echo "FAIL: $SCRIPT not executable" >&2; exit 1; }
[ -x "$FAKE_BUILD" ] || { echo "FAIL: $FAKE_BUILD not executable" >&2; exit 1; }

PASS=0
FAIL=0

assert_file() {
  local f="$1"
  if [ -f "$f" ]; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: missing $f" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_grep() {
  local pattern="$1" file="$2"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: pattern '$pattern' not found in $file" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Each scenario gets a fresh sandbox to avoid leaking state between runs.
make_sandbox() {
  local sandbox="$1"
  rm -rf "$sandbox"
  mkdir -p "$sandbox/site/src"

  cd "$sandbox/site"
  git init -q -b main
  git config user.email test@example.com
  git config user.name test

  # Builder lives at the repo root so historical clones inherit it via the tag.
  cp "$FAKE_BUILD" ./fake-build.sh
  chmod +x ./fake-build.sh

  echo '[{"key":"current","label":"current"}]' > src/versions.json
  git add .
  git commit -q -m "initial"
  git tag v0.9

  git commit --allow-empty -q -m "1.0 release"
  git tag v1.0

  cat > deploy-versions.json <<'EOF'
[
  {"key":"0.9","tag":"v0.9"},
  {"key":"1.0","tag":"v1.0"}
]
EOF
  git add deploy-versions.json
  git commit -q -m "add deploy-versions"
}

run_scenario() {
  local name="$1"
  shift
  echo
  echo "scenario: $name"
  "$@"
}

# --- Scenario 1: no SITE_BASE, default settings -----------------------------

scenario_default() {
  local sandbox
  sandbox="$(mktemp -d)"
  # shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
  trap "rm -rf $sandbox" RETURN
  make_sandbox "$sandbox"

  REPO_URL="file://$sandbox/site" \
  INSTALL_CMD="true" \
  BUILD_CMD="./fake-build.sh" \
  DIST_DIR="$sandbox/site/dist" \
  BUILD_DIR="$sandbox/site/build" \
    "$SCRIPT" >/dev/null

  for key in 0.9 1.0 next; do
    assert_file "$sandbox/site/dist/$key/index.html"
    assert_grep "site-version-key\" content=\"$key\"" "$sandbox/site/dist/$key/index.html"
  done

  # Per-version `versions.json` is the unmutated source seed (the snapshot
  # of versions known at build time). Each historical clone keeps its own
  # seed; the orchestrator no longer overwrites it.
  assert_grep "current" "$sandbox/site/dist/next/versions.json"

  # Canonical merged manifest at the docroot is what runtime/hybrid switcher
  # shims fetch. It contains deploy-versions entries plus `next` (HEAD), but
  # NOT the seed's self-reference ("current") since that doesn't map to a
  # navigable URL.
  assert_file "$sandbox/site/dist/versions.json"
  assert_grep "0.9"  "$sandbox/site/dist/versions.json"
  assert_grep "1.0"  "$sandbox/site/dist/versions.json"
  assert_grep "next" "$sandbox/site/dist/versions.json"

  # The switcher shim is dropped into every per-version output dir so each
  # version's <script src="./switcher.js"> resolves locally.
  for key in 0.9 1.0 next; do
    assert_file "$sandbox/site/dist/$key/switcher.js"
  done
}

# --- Scenario 2: SITE_BASE set ----------------------------------------------

scenario_site_base() {
  local sandbox
  sandbox="$(mktemp -d)"
  # shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
  trap "rm -rf $sandbox" RETURN
  make_sandbox "$sandbox"

  REPO_URL="file://$sandbox/site" \
  INSTALL_CMD="true" \
  BUILD_CMD="./fake-build.sh" \
  DIST_DIR="$sandbox/site/dist" \
  BUILD_DIR="$sandbox/site/build" \
  SITE_BASE="my-docs" \
    "$SCRIPT" >/dev/null

  for key in 0.9 1.0 next; do
    assert_file "$sandbox/site/dist/my-docs/$key/index.html"
    assert_grep "site-base\" content=\"my-docs\"" "$sandbox/site/dist/my-docs/$key/index.html"
  done

  # Canonical manifest lives under the SITE_BASE prefix.
  assert_file "$sandbox/site/dist/my-docs/versions.json"
  assert_grep "0.9" "$sandbox/site/dist/my-docs/versions.json"
}

# --- Scenario 3: empty deploy-versions.json (only HEAD) ---------------------

scenario_empty_versions() {
  local sandbox
  sandbox="$(mktemp -d)"
  # shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
  trap "rm -rf $sandbox" RETURN
  make_sandbox "$sandbox"

  cd "$sandbox/site"
  echo '[]' > deploy-versions.json
  git add deploy-versions.json
  git commit -q -m "drop historical versions"

  REPO_URL="file://$sandbox/site" \
  INSTALL_CMD="true" \
  BUILD_CMD="./fake-build.sh" \
  DIST_DIR="$sandbox/site/dist" \
  BUILD_DIR="$sandbox/site/build" \
    "$SCRIPT" >/dev/null

  assert_file "$sandbox/site/dist/next/index.html"
  if [ -d "$sandbox/site/dist/0.9" ] || [ -d "$sandbox/site/dist/1.0" ]; then
    echo "  FAIL: historical dirs present when deploy-versions is empty" >&2
    FAIL=$((FAIL + 1))
  else
    PASS=$((PASS + 1))
  fi
}

# --- Scenario 4: SHA-keyed cache (hit + miss) -------------------------------

scenario_cache() {
  local sandbox cache rc
  sandbox="$(mktemp -d)"
  cache="$(mktemp -d)"
  # shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
  trap "rm -rf $sandbox $cache" RETURN
  make_sandbox "$sandbox"

  # First run: cold cache, both historical entries should write to it.
  REPO_URL="file://$sandbox/site" \
  INSTALL_CMD="true" \
  BUILD_CMD="./fake-build.sh" \
  DIST_DIR="$sandbox/site/dist" \
  BUILD_DIR="$sandbox/site/build" \
  CACHE_DIR="$cache" \
    "$SCRIPT" > "$sandbox/run1.log" 2>&1

  for key in 0.9 1.0; do
    if find "$cache" -path "*/$key/index.html" -print -quit | grep -q .; then
      PASS=$((PASS + 1))
    else
      echo "  FAIL: no cache entry written for $key after cold run" >&2
      FAIL=$((FAIL + 1))
    fi
  done

  # Wipe the dist dir so we can detect that the second run restored from cache
  # rather than rebuilding.
  rm -rf "$sandbox/site/dist"

  # Second run: warm cache, historical builds should be served from cache and
  # not invoke fake-build.sh. We strip the build script's executable bit so
  # the orchestrator would fail loudly if it tried to invoke it.
  chmod -x "$sandbox/site/fake-build.sh"

  rc=0
  REPO_URL="file://$sandbox/site" \
  INSTALL_CMD="true" \
  BUILD_CMD="./fake-build.sh" \
  DIST_DIR="$sandbox/site/dist" \
  BUILD_DIR="$sandbox/site/build" \
  CACHE_DIR="$cache" \
    "$SCRIPT" > "$sandbox/run2.log" 2>&1 || rc=$?
  chmod +x "$sandbox/site/fake-build.sh"

  # HEAD always rebuilds, and HEAD's BUILD_CMD will fail because the script
  # is non-executable. We only care that historicals were cache-hit; rc != 0
  # is expected. Just check the historical entries were restored.
  for key in 0.9 1.0; do
    assert_file "$sandbox/site/dist/$key/index.html"
  done

  if grep -q "cache hit" "$sandbox/run2.log"; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: warm run did not log a cache hit" >&2
    FAIL=$((FAIL + 1))
  fi

  # Sanity: rc is non-zero (HEAD build was supposed to fail).
  if [ "$rc" -ne 0 ]; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: HEAD build was expected to fail (script non-executable) but rc=0" >&2
    FAIL=$((FAIL + 1))
  fi
}

run_scenario "default settings"         scenario_default
run_scenario "with SITE_BASE prefix"    scenario_site_base
run_scenario "empty deploy-versions"    scenario_empty_versions
run_scenario "SHA cache hit/miss"       scenario_cache

echo
echo "results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
