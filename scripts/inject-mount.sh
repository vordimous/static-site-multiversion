#!/usr/bin/env bash
#
# Post-processes a per-version output directory and injects the bolted
# version-switcher mount into every HTML file that has no dropdown of
# its own. Lets historical builds (whose source commits predate the
# switcher integration) ship a working version dropdown without
# rewriting any tags.
#
# The injected mount uses runtime mode (no inline seed) and points its
# data-canonical / data-fallback at absolute URLs so the shim works
# from nested pages, not just the per-version landing.
#
# Usage:
#   scripts/inject-mount.sh <out_dir> <url_base> [next_key]
#
# Args:
#   out_dir   per-version output directory, e.g. .demo/_serve/eleventy/0.9
#   url_base  absolute URL prefix this per-version dir is served at,
#             e.g. /eleventy/0.9 (local) or /static-site-multiversion/eleventy/0.9 (Pages)
#   next_key  version key of the HEAD build, used for the fallback link
#             (default: next)
#
# Skipped if the page already has a dropdown (any of):
#   #version-switcher    .vp-version-menu    .vp-navbar-dropdown
#   .dropdown-toggle     .dropdown__menu
#
# These markers cover the bolted shim plus the native nav-bar dropdowns
# of vitepress, vuepress, mkdocs, and docusaurus. plain-html / eleventy /
# hugo / astro use the bolted marker, so HEAD pages with the mount are
# left alone too.

set -euo pipefail

OUT_DIR="${1:?inject-mount: out_dir required}"
URL_BASE="${2:?inject-mount: url_base required}"
NEXT_KEY="${3:-next}"

[ -d "$OUT_DIR" ] || { echo "inject-mount: $OUT_DIR not a directory" >&2; exit 1; }

# Builder root one level up from the per-version dir. canonical /
# fallback live at <builder>/versions.json and <builder>/next/. Empty when
# there is no SITE_BASE, so the joins below yield /versions.json rather than
# the protocol-relative //versions.json.
BUILDER_BASE="${URL_BASE%/*}"

CANONICAL="$BUILDER_BASE/versions.json"
FALLBACK="$BUILDER_BASE/$NEXT_KEY/"
SCRIPT_SRC="$URL_BASE/switcher.js"

# Markers any of which means "this page already has a working dropdown".
# Kept in sync with scripts/switcher-tour.mjs's per-builder selectors.
read -r -d '' DROPDOWN_MARKERS <<'EOF' || true
id="version-switcher"
vp-version-menu
vp-navbar-dropdown
dropdown-toggle
dropdown__menu
EOF

has_dropdown() {
  local file="$1" m
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    if grep -q -F "$m" "$file"; then
      return 0
    fi
  done <<< "$DROPDOWN_MARKERS"
  return 1
}

# Block injected before </body>. Single-line so sed can splice it in
# without managing a heredoc temp file.
SNIPPET=$(printf '<div id="version-switcher" data-mode="runtime" data-canonical="%s" data-fallback="%s"></div><script src="%s" defer></script>' \
  "$CANONICAL" "$FALLBACK" "$SCRIPT_SRC")

injected=0
skipped=0
no_body=0

while IFS= read -r -d '' file; do
  if has_dropdown "$file"; then
    skipped=$((skipped + 1))
    continue
  fi
  if ! grep -q '</body>' "$file"; then
    # No </body> tag — frameworks that ship pages without one (rare)
    # would need a different injection point. Report so we notice.
    no_body=$((no_body + 1))
    continue
  fi
  # perl rather than sed to avoid BSD-vs-GNU differences in the in-place
  # flag. -0777 reads the whole file as one record, so the match works no
  # matter which line </body> is on; the greedy (.*) targets the last one.
  SNIPPET="$SNIPPET" perl -0777 -i -pe 's{(.*)</body>}{$1$ENV{SNIPPET}</body>}s' "$file"
  injected=$((injected + 1))
done < <(find "$OUT_DIR" -type f -name '*.html' -print0)

echo "inject-mount: $OUT_DIR (base=$URL_BASE) injected=$injected skipped=$skipped no_body=$no_body"
