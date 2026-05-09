#!/usr/bin/env bash
#
# Wires the static-site-multiversion builder contract into a plain-HTML site.
#
# This is the contract distilled. There is no generator. The "build" copies
# src/ to $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/. Every other example in
# this repo is a real generator doing the same thing under more layers.

set -euo pipefail

: "${SITE_VERSION_KEY:?SITE_VERSION_KEY is required}"
: "${DIST_DIR:?DIST_DIR is required}"

out="$DIST_DIR"
if [ -n "${SITE_BASE:-}" ]; then
  out="$out/$SITE_BASE"
fi
out="$out/$SITE_VERSION_KEY"

mkdir -p "$out"
cp -R src/. "$out/"

echo "plain-html: wrote $out/"
