#!/usr/bin/env bash
#
# Stand-in for a real static-site builder. Honors the same contract every
# example builder must honor: read SITE_VERSION_KEY, DIST_DIR, and optionally
# SITE_BASE from env, then write build output to
# $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/.
#
# Used by test/test-build-versions.sh to exercise scripts/build-versions.sh
# without pulling in a real Node/Python/etc. toolchain.

set -euo pipefail

: "${SITE_VERSION_KEY:?fake-build: SITE_VERSION_KEY is required}"
: "${DIST_DIR:?fake-build: DIST_DIR is required}"

out="$DIST_DIR"
if [ -n "${SITE_BASE:-}" ]; then
  out="$out/$SITE_BASE"
fi
out="$out/$SITE_VERSION_KEY"

mkdir -p "$out"

cat > "$out/index.html" <<EOF
<!doctype html>
<title>fake-build</title>
<meta name="site-version-key" content="$SITE_VERSION_KEY">
<meta name="site-base" content="${SITE_BASE:-}">
EOF

# Echo the version-switcher manifest so tests can assert it was injected.
if [ -f src/versions.json ]; then
  cp src/versions.json "$out/versions.json"
fi

echo "fake-build: wrote $out/index.html"
