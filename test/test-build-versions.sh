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

  # Manifest shape: valid JSON array of exactly the three navigable keys, in
  # the documented order (deploy-versions entries first, HEAD last).
  if jq -e '. | length == 3 and .[0].key == "0.9" and .[1].key == "1.0" and .[2].key == "next"' \
        "$sandbox/site/dist/versions.json" >/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: canonical manifest has unexpected shape" >&2
    FAIL=$((FAIL + 1))
  fi

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

# --- Scenario 5: annotated tags resolve to commit SHA, not tag-object SHA ---
#
# Lightweight tags point directly at a commit, so `git ls-remote refs/tags/X`
# returns the commit SHA. Annotated tags wrap a tag object around the commit,
# so the same lookup returns the tag-object SHA and the cache key would never
# match the actual build. resolve_sha must use the `^{}` peel suffix to
# dereference annotated tags to their target commit.

scenario_annotated_tag() {
  local sandbox cache annotated_sha cached_dir
  sandbox="$(mktemp -d)"
  cache="$(mktemp -d)"
  # shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
  trap "rm -rf $sandbox $cache" RETURN
  make_sandbox "$sandbox"

  cd "$sandbox/site"
  # Replace v0.9 with an annotated tag pointing at the same commit. Capture
  # the commit SHA before deleting the lightweight tag.
  local v09_commit
  v09_commit="$(git rev-parse v0.9)"
  git tag -d v0.9 >/dev/null
  git tag -a v0.9 -m "annotated 0.9" "$v09_commit"

  REPO_URL="file://$sandbox/site" \
  INSTALL_CMD="true" \
  BUILD_CMD="./fake-build.sh" \
  DIST_DIR="$sandbox/site/dist" \
  BUILD_DIR="$sandbox/site/build" \
  CACHE_DIR="$cache" \
    "$SCRIPT" >/dev/null

  # The cache should be keyed under the *commit* SHA (what git rev-parse
  # returns for the tag's target), not the tag-object SHA.
  annotated_sha="$(git -C "$sandbox/site" rev-parse 'v0.9^{}')"
  cached_dir="$cache/$annotated_sha/0.9"
  if [ -f "$cached_dir/index.html" ]; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: annotated tag cached under wrong SHA (expected $annotated_sha)" >&2
    FAIL=$((FAIL + 1))
  fi
}

# --- Scenario 6: nested pages reach switcher.js via relative href -----------
#
# The orchestrator copies scripts/switcher.js into every per-version output
# root. A page at <key>/sub/page.html that references `../switcher.js` must
# resolve to that copy — i.e. switcher.js must land at the per-version root,
# not deeper. This guards the "no per-example asset wiring required" promise.

scenario_nested_pages() {
  local sandbox
  sandbox="$(mktemp -d)"
  # shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
  trap "rm -rf $sandbox" RETURN
  make_sandbox "$sandbox"

  # Extend the fake builder so it also writes a nested page that references
  # ../switcher.js. Only HEAD runs from this updated builder; the historical
  # clones still use the original fake-build.sh from their tag (tags are
  # immutable). That's fine for this scenario — the orchestrator runs
  # copy_switcher uniformly, so any per-version output dir validates the
  # claim.
  cat > "$sandbox/site/fake-build.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
: "${SITE_VERSION_KEY:?}"
: "${DIST_DIR:?}"
out="$DIST_DIR"
[ -n "${SITE_BASE:-}" ] && out="$out/$SITE_BASE"
out="$out/$SITE_VERSION_KEY"
mkdir -p "$out/sub"
echo "<!doctype html><title>$SITE_VERSION_KEY</title>" > "$out/index.html"
cat > "$out/sub/page.html" <<HTML
<!doctype html><title>nested</title>
<div id="version-switcher"></div>
<script src="../switcher.js" defer></script>
HTML
EOF
  chmod +x "$sandbox/site/fake-build.sh"

  REPO_URL="file://$sandbox/site" \
  INSTALL_CMD="true" \
  BUILD_CMD="./fake-build.sh" \
  DIST_DIR="$sandbox/site/dist" \
  BUILD_DIR="$sandbox/site/build" \
    "$SCRIPT" >/dev/null

  assert_file "$sandbox/site/dist/next/sub/page.html"
  # The reference target of `../switcher.js` from next/sub/page.html resolves
  # to next/switcher.js — the orchestrator's copy_switcher must have placed
  # it there. Also check the historical keys got their copy at the right
  # depth (their build doesn't write the nested page, but copy_switcher
  # still runs).
  for key in 0.9 1.0 next; do
    assert_file "$sandbox/site/dist/$key/switcher.js"
  done
}

# --- Scenario 7: NEXT_LABEL customizes the HEAD entry's dropdown label ------

scenario_next_label() {
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
  NEXT_LABEL="Latest" \
    "$SCRIPT" >/dev/null

  if jq -e '.[-1] | .key == "next" and .label == "Latest"' \
        "$sandbox/site/dist/versions.json" >/dev/null; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: NEXT_LABEL not applied to HEAD entry" >&2
    FAIL=$((FAIL + 1))
  fi
}

run_scenario "default settings"         scenario_default
run_scenario "with SITE_BASE prefix"    scenario_site_base
run_scenario "empty deploy-versions"    scenario_empty_versions
run_scenario "SHA cache hit/miss"       scenario_cache
run_scenario "annotated tags peel SHA"  scenario_annotated_tag
run_scenario "nested-page switcher"     scenario_nested_pages
run_scenario "NEXT_LABEL custom"        scenario_next_label

echo
echo "results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
