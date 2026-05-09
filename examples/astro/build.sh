#!/usr/bin/env bash
#
# Wraps `astro build` for the static-site-multiversion contract. Astro
# can't reliably write directly to an outDir outside the project cwd
# (see notes in astro.config.mjs), so we let it write to the default
# ./dist and copy from there to the env-derived target.

set -euo pipefail

: "${SITE_VERSION_KEY:?SITE_VERSION_KEY is required}"
: "${DIST_DIR:?DIST_DIR is required}"

# Always run astro from the example dir, regardless of where we were
# invoked from.
cd "$(dirname "$0")"

target="$DIST_DIR"
if [ -n "${SITE_BASE:-}" ]; then
  target="$target/$SITE_BASE"
fi
target="$target/$SITE_VERSION_KEY"

mkdir -p "$target"

./node_modules/.bin/astro build

cp -R dist/. "$target/"

echo "astro: wrote $target/"
