#!/usr/bin/env bash
#
# Wires the versioned-jamstack-examples builder contract into MkDocs.
#
# MkDocs reads its config from mkdocs.yml and doesn't natively read env vars,
# so this thin wrapper maps SITE_VERSION_KEY / SITE_BASE / DIST_DIR onto the
# mkdocs CLI flags `--site-dir` (output path) and `--site-url` (URL prefix).

set -euo pipefail

versionKey="${SITE_VERSION_KEY:-next}"
siteBase="${SITE_BASE:-}"
distRoot="${DIST_DIR:-$(pwd)/../../dist}"

outDir="$distRoot"
if [ -n "$siteBase" ]; then
  outDir="$outDir/$siteBase"
fi
outDir="$outDir/$versionKey"

mkdir -p "$outDir"

mkdocs build \
  --clean \
  --site-dir "$outDir" \
  --no-strict
