#!/usr/bin/env bash
#
# Wires the static-site-multiversion builder contract into MkDocs.
#
# MkDocs reads its config from mkdocs.yml and doesn't natively read env vars,
# so this thin wrapper maps SITE_VERSION_KEY / SITE_BASE / DIST_DIR onto the
# mkdocs CLI flags `--site-dir` (output path) and `--site-url` (URL prefix).
#
# This wrapper also bakes a Versions dropdown into the navbar by appending
# a synthesized `nav:` entry to a temp copy of mkdocs.yml. Items come from
# the orchestrator-exported $DEPLOY_VERSIONS file plus the build-time
# version slug, so the dropdown is frozen at build time (baked mode).

set -euo pipefail

cd "$(dirname "$0")"

versionKey="${SITE_VERSION_KEY:-next}"
siteBase="${SITE_BASE:-}"
distRoot="${DIST_DIR:-$(pwd)/../../dist}"

outDir="$distRoot"
if [ -n "$siteBase" ]; then
  outDir="$outDir/$siteBase"
fi
outDir="$outDir/$versionKey"

mkdir -p "$outDir"

# Build the Versions nav block from DEPLOY_VERSIONS + the current key.
builderBase="/"
if [ -n "$siteBase" ]; then
  builderBase="/$siteBase/"
fi

# Place the temp config alongside mkdocs.yml so docs_dir (relative to the
# config file's directory by mkdocs convention) still resolves to ./docs.
tmpConfig="./.mkdocs-versioned.yml"
trap 'rm -f "$tmpConfig"' EXIT
cp mkdocs.yml "$tmpConfig"

{
  printf '\n# Appended by build.sh: per-build versions dropdown.\n'
  printf 'nav:\n  - Home: index.md\n  - Guide: guide.md\n  - Versions:\n'
  if [ -n "${DEPLOY_VERSIONS:-}" ] && [ -f "$DEPLOY_VERSIONS" ]; then
    # jq -> YAML lines, skipping `current` self-references.
    jq -r --arg base "$builderBase" --arg key "$versionKey" '
      .[] | select(.key != "current") |
      "    - \"\(.label // .key)\": \"\($base)\(.key)/\""
    ' "$DEPLOY_VERSIONS"
  fi
  # Always include the current build's slug.
  printf '    - "%s": "%s%s/"\n' "$versionKey" "$builderBase" "$versionKey"
} >> "$tmpConfig"

# Strip the original `nav:` block from the source mkdocs.yml since we just
# appended a fresh one. (Use a Python one-liner to preserve YAML structure.)
python3 - "$tmpConfig" <<'PY'
import sys, re
path = sys.argv[1]
with open(path) as f:
    text = f.read()
# Remove the original nav: block (the first one) but keep the appended one.
# The first nav: block is the one in the source file; the appended one is
# after our marker comment.
marker = "# Appended by build.sh: per-build versions dropdown."
src, _, appended = text.partition(marker)
# Drop everything from the first "nav:" through to the marker (or EOF in src).
src = re.sub(r'(?ms)^nav:\s*(?:^[ \t-].*\n?)+', '', src)
with open(path, 'w') as f:
    f.write(src.rstrip() + '\n' + marker + appended)
PY

mkdocs build \
  --config-file "$tmpConfig" \
  --clean \
  --site-dir "$outDir" \
  --no-strict
