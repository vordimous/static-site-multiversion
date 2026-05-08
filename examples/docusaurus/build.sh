#!/usr/bin/env bash
#
# Wires the versioned-jamstack-examples builder contract into Docusaurus.
#
# Docusaurus reads baseUrl from docusaurus.config.js (which itself reads
# SITE_VERSION_KEY / SITE_BASE from env) but the output directory must be
# passed via the --out-dir CLI flag. This wrapper computes the per-version
# path from the env vars and invokes docusaurus with the right destination.

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

npx --no-install docusaurus build --out-dir "$outDir"
