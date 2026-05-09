#!/usr/bin/env bash
#
# Wraps `astro build` for the v3 era of the static-site-multiversion
# contract. Astro 3 can't write directly to an outDir outside the project
# cwd, so we let it write to the default ./dist and copy from there to the
# env-derived target. The astro-v4 tag (and master) write outDir directly
# in astro.config.mjs and don't need this wrapper.

set -euo pipefail

: "${SITE_VERSION_KEY:?SITE_VERSION_KEY is required}"
: "${DIST_DIR:?DIST_DIR is required}"

target="$DIST_DIR"
if [ -n "${SITE_BASE:-}" ]; then
  target="$target/$SITE_BASE"
fi
target="$target/$SITE_VERSION_KEY"

mkdir -p "$target"

npx astro build

cp -R dist/. "$target/"

echo "astro: wrote $target/"
