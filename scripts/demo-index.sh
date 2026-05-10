#!/usr/bin/env bash
#
# Writes the top-level landing page (index.html) and cross-builder index
# (versions.json) for the multi-version demo docroot. Split out of
# scripts/demo-all.sh so CI can call it after assembling per-builder
# artifacts produced by parallel matrix jobs, without re-running any builds.
#
# Usage:
#   scripts/demo-index.sh                         # uses .demo/_serve
#   PUBLISH_ROOT=path/to/serve scripts/demo-index.sh
#   SITE_BASE_PREFIX=foo scripts/demo-index.sh    # nests under .demo/_serve/foo/
#
# Scans the publish root for per-builder subdirectories (matching the
# canonical builder list) and lists whichever ones it finds. Missing
# builders are silently skipped, so this works for partial builds too.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SERVE_ROOT="${SERVE_ROOT:-$REPO_ROOT/.demo/_serve}"
SITE_BASE_PREFIX="${SITE_BASE_PREFIX:-}"

PUBLISH_ROOT="${PUBLISH_ROOT:-}"
if [ -z "$PUBLISH_ROOT" ]; then
  PUBLISH_ROOT="$SERVE_ROOT"
  if [ -n "$SITE_BASE_PREFIX" ]; then
    PUBLISH_ROOT="$SERVE_ROOT/$SITE_BASE_PREFIX"
  fi
fi

[ -d "$PUBLISH_ROOT" ] || { echo "demo-index: $PUBLISH_ROOT not found" >&2; exit 1; }

# Canonical builder ordering. Kept in sync with scripts/demo-all.sh.
ALL_BUILDERS=(plain-html vuepress vitepress astro docusaurus eleventy hugo mkdocs)

write_index() {
  local out="$PUBLISH_ROOT/index.html"
  {
    cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>static-site-multiversion local demo</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body { font-family: system-ui, sans-serif; max-width: 48rem; margin: 2rem auto; padding: 0 1rem; }
    h1 { margin-bottom: 0.25rem; }
    .lead { color: #555; margin-top: 0; }
    table { border-collapse: collapse; width: 100%; margin-top: 1rem; }
    th, td { text-align: left; padding: 0.4rem 0.6rem; border-bottom: 1px solid #eee; }
    code { background: #f4f4f4; padding: 0 0.25rem; border-radius: 3px; }
  </style>
</head>
<body>
  <h1>static-site-multiversion</h1>
  <p class="lead">Local multi-version demo. Each row is the same site, built by a different generator from the same git history.</p>
  <table>
    <thead><tr><th>Builder</th><th>Versions</th></tr></thead>
    <tbody>
HTML
    for b in "${ALL_BUILDERS[@]}"; do
      [ -d "$PUBLISH_ROOT/$b" ] || continue
      printf '      <tr><td><strong>%s</strong></td><td>' "$b"
      versions=()
      while IFS= read -r v; do
        versions+=("$v")
      done < <(find "$PUBLISH_ROOT/$b" -mindepth 1 -maxdepth 1 -type d -not -name next -exec basename {} \; 2>/dev/null | sort)
      [ -d "$PUBLISH_ROOT/$b/next" ] && versions+=(next)
      for k in "${versions[@]}"; do
        printf '<a href="./%s/%s/">%s</a> ' "$b" "$k" "$k"
      done
      printf '</td></tr>\n'
    done
    cat <<'HTML'
    </tbody>
  </table>
</body>
</html>
HTML
  } > "$out"
  echo "wrote $out"
}

write_cross_index() {
  local out="$PUBLISH_ROOT/versions.json"
  local url_prefix="/"
  if [ -n "$SITE_BASE_PREFIX" ]; then
    url_prefix="/$SITE_BASE_PREFIX/"
  fi
  {
    printf '{\n  "builders": [\n'
    local first=1
    for b in "${ALL_BUILDERS[@]}"; do
      [ -d "$PUBLISH_ROOT/$b" ] || continue
      [ -f "$PUBLISH_ROOT/$b/versions.json" ] || continue
      if [ "$first" -eq 0 ]; then printf ',\n'; fi
      first=0
      printf '    { "name": "%s", "versions": "%s%s/versions.json", "default": "next" }' "$b" "$url_prefix" "$b"
    done
    printf '\n  ]\n}\n'
  } > "$out"
  echo "wrote $out"
}

write_index
write_cross_index
