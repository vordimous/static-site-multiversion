#!/usr/bin/env bash
#
# Tests for scripts/inject-mount.sh: which pages get the bolted switcher
# mount, that a second pass is a no-op, and that the injected URLs are right
# for both URL layouts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INJECT="$REPO_ROOT/scripts/inject-mount.sh"

PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $desc" >&2
    FAIL=$((FAIL + 1))
  fi
}

count() { grep -o -F "$1" "$2" | wc -l | tr -d ' '; }

sandbox="$(mktemp -d)"
# shellcheck disable=SC2064  # capture sandbox path at trap-set time on purpose
trap "rm -rf $sandbox" EXIT

# --- Scenario 1: SITE_BASE layout -------------------------------------------

echo
echo "scenario: pages under /docs/1.0"
out="$sandbox/docs/1.0"
mkdir -p "$out/sub"
echo '<html><body><p>plain</p></body></html>' > "$out/index.html"
echo '<html><body><p>nested</p></body></html>' > "$out/sub/page.html"
echo '<html><body><div class="vp-version-menu"></div></body></html>' > "$out/native.html"
echo '<html><p>no body tag</p></html>' > "$out/fragment.html"
cp "$out/native.html" "$sandbox/native.orig"
cp "$out/fragment.html" "$sandbox/fragment.orig"

"$INJECT" "$out" /docs/1.0 >/dev/null
"$INJECT" "$out" /docs/1.0 >/dev/null

check "plain page gets exactly one mount" [ "$(count 'id="version-switcher"' "$out/index.html")" = 1 ]
check "nested page gets exactly one mount" [ "$(count 'id="version-switcher"' "$out/sub/page.html")" = 1 ]
check "canonical points at the builder root" grep -q -F 'data-canonical="/docs/versions.json"' "$out/index.html"
check "fallback points at next" grep -q -F 'data-fallback="/docs/next/"' "$out/index.html"
check "script loads from the version root" grep -q -F 'src="/docs/1.0/switcher.js"' "$out/sub/page.html"
check "page with a native dropdown is untouched" cmp -s "$out/native.html" "$sandbox/native.orig"
check "page without </body> is untouched" cmp -s "$out/fragment.html" "$sandbox/fragment.orig"

# --- Scenario 2: no SITE_BASE -----------------------------------------------
#
# The builder root is "/", so a naive "$base/versions.json" yields
# "//versions.json", a protocol-relative URL pointing at another host.

echo
echo "scenario: pages under /1.0"
out="$sandbox/root/1.0"
mkdir -p "$out"
echo '<html><body></body></html>' > "$out/index.html"

"$INJECT" "$out" /1.0 >/dev/null

check "canonical is /versions.json" grep -q -F 'data-canonical="/versions.json"' "$out/index.html"
check "fallback is /next/" grep -q -F 'data-fallback="/next/"' "$out/index.html"
check "script loads from /1.0/" grep -q -F 'src="/1.0/switcher.js"' "$out/index.html"

out="$sandbox/custom/1.0"
mkdir -p "$out"
echo '<html><body></body></html>' > "$out/index.html"
"$INJECT" "$out" /docs/1.0 latest >/dev/null
check "fallback follows a custom next key" grep -q -F 'data-fallback="/docs/latest/"' "$out/index.html"

echo
echo "results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
