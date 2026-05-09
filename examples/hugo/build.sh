#!/usr/bin/env bash
#
# Wires the static-site-multiversion builder contract into Hugo.
#
# Hugo accepts both --baseURL and --destination as CLI flags, so this wrapper
# reads SITE_VERSION_KEY / SITE_BASE / DIST_DIR from the env and passes them
# through. No changes to hugo.toml are needed at build time.

set -euo pipefail

versionKey="${SITE_VERSION_KEY:-next}"
siteBase="${SITE_BASE:-}"
distRoot="${DIST_DIR:-$(pwd)/../../dist}"

outDir="$distRoot"
if [ -n "$siteBase" ]; then
  outDir="$outDir/$siteBase"
fi
outDir="$outDir/$versionKey"

if [ -n "$siteBase" ]; then
  baseURL="/$siteBase/$versionKey/"
else
  baseURL="/$versionKey/"
fi

mkdir -p "$outDir"

hugo \
  --baseURL "$baseURL" \
  --destination "$outDir" \
  --cleanDestinationDir
