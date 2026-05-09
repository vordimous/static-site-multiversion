#!/usr/bin/env bash
#
# Portable multi-version static site build orchestrator.
#
# Builds the current repo at HEAD as `next`, plus one historical version per
# entry in deploy-versions.json. All output lands in $DIST_DIR under per-version
# subdirectories. Works in any CI provider and locally; only requires bash, git,
# and jq.
#
# Required env:
#   REPO_URL            git URL to clone historical versions from
#
# Optional env (with defaults):
#   DEPLOY_VERSIONS     path to deploy-versions.json   (default: deploy-versions.json)
#   VERSIONS_MANIFEST   path inside site to the
#                       version-switcher manifest      (default: src/versions.json)
#   DIST_DIR            shared output directory        (default: $PWD/dist)
#   BUILD_DIR           where historical clones land   (default: $PWD/build)
#   SITE_BASE           URL path prefix, if any        (default: empty)
#   INSTALL_CMD         install command per version    (default: pnpm install)
#   BUILD_CMD           build command per version      (default: pnpm build)
#   NEXT_KEY            version key for HEAD           (default: next)
#   SWITCHER_JS         path to switcher.js to copy
#                       into each per-version output   (default: $script_dir/switcher.js)
#   CACHE_DIR           SHA-keyed artifact cache root  (default: empty = disabled)
#
# INSTALL_CMD and BUILD_CMD are passed through `eval`, so they accept full
# shell syntax (pipes, &&, subshells). Quote anything that needs to survive
# expansion at the call site.
#
# Builder contract: each build must honor SITE_VERSION_KEY and DIST_DIR (and
# SITE_BASE when set), writing output to:
#   $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/
#
# Versioning model:
#   - Each version's source `versions.json` (e.g. src/versions.json) is the
#     "seed" snapshot of versions known at build time. The orchestrator no
#     longer overwrites it; historical clones keep their committed seed.
#   - After all per-version builds, the orchestrator writes the MERGED list
#     (seed + deploy-versions) to $DIST_DIR/[$SITE_BASE/]versions.json. This
#     is the "canonical" runtime list — switcher shims (scripts/switcher.js
#     mode=runtime|hybrid) fetch ../versions.json to discover newer versions
#     added after their build.
#   - SWITCHER_JS, if present, is copied into every per-version output dir
#     so each version's <script src="./switcher.js"> resolves locally.

set -euo pipefail

: "${REPO_URL:?REPO_URL is required}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DEPLOY_VERSIONS="${DEPLOY_VERSIONS:-deploy-versions.json}"
VERSIONS_MANIFEST="${VERSIONS_MANIFEST:-src/versions.json}"
DIST_DIR="${DIST_DIR:-$PWD/dist}"
BUILD_DIR="${BUILD_DIR:-$PWD/build}"
SITE_BASE="${SITE_BASE:-}"
INSTALL_CMD="${INSTALL_CMD:-pnpm install}"
BUILD_CMD="${BUILD_CMD:-pnpm build}"
NEXT_KEY="${NEXT_KEY:-next}"
SWITCHER_JS="${SWITCHER_JS:-$SCRIPT_DIR/switcher.js}"
CACHE_DIR="${CACHE_DIR:-}"

if [ ! -f "$DEPLOY_VERSIONS" ]; then
  echo "build-versions: $DEPLOY_VERSIONS not found" >&2
  exit 1
fi

if [ ! -f "$VERSIONS_MANIFEST" ]; then
  echo "build-versions: $VERSIONS_MANIFEST not found" >&2
  exit 1
fi

mkdir -p "$DIST_DIR" "$BUILD_DIR"

# Per-builder canonical output prefix: $DIST_DIR/[$SITE_BASE/]
canonical_prefix="$DIST_DIR"
if [ -n "$SITE_BASE" ]; then
  canonical_prefix="$canonical_prefix/$SITE_BASE"
fi
mkdir -p "$canonical_prefix"

# Resolves the per-key output dir under the canonical prefix.
key_outdir() { printf '%s/%s' "$canonical_prefix" "$1"; }

# 1. Compose the canonical manifest. This is the list switcher shims fetch
#    at runtime, so it lists every navigable version: deploy-versions.json
#    entries (the historical tags/branches) plus a `next` entry for HEAD.
#    The example's own seed (`$VERSIONS_MANIFEST`) is left untouched and is
#    NOT merged in — the seed is the page's own per-build snapshot, which
#    doesn't map to a navigable URL on its own (it typically reads "current"
#    or similar self-reference).
MERGED_MANIFEST="$(mktemp -t merged-versions.XXXXXX)"
trap 'rm -f "$MERGED_MANIFEST"' EXIT
NEXT_ENTRY="$(jq -nc --arg k "$NEXT_KEY" '[{ key: $k, label: $k }]')"
jq -s '.[0] + .[1]' "$DEPLOY_VERSIONS" <(printf '%s' "$NEXT_ENTRY") > "$MERGED_MANIFEST"

echo "build-versions: canonical manifest composed (deploy-versions + $NEXT_KEY)"

# Resolves a tag (or branch) into its commit SHA inside the source repo.
resolve_sha() {
  git ls-remote "$REPO_URL" "refs/tags/$1" "refs/heads/$1" 2>/dev/null \
    | head -n1 | awk '{print $1}'
}

# Drops a switcher.js into the per-version output dir, when configured.
copy_switcher() {
  local key="$1" out
  out="$(key_outdir "$key")"
  if [ -n "$SWITCHER_JS" ] && [ -f "$SWITCHER_JS" ]; then
    cp "$SWITCHER_JS" "$out/switcher.js"
  fi
}

# 2. Build each historical version into the shared $DIST_DIR. If $CACHE_DIR is
#    configured and we have a SHA match for the tag, restore the cached output
#    instead of cloning + rebuilding.
WRKDIR="$PWD"

while IFS= read -r row; do
  key=$(echo "$row" | base64 --decode | jq -r '.key')
  tag=$(echo "$row" | base64 --decode | jq -r '.tag')

  out_dir="$(key_outdir "$key")"

  if [ -n "$CACHE_DIR" ]; then
    sha="$(resolve_sha "$tag")"
    if [ -n "$sha" ]; then
      cache_path="$CACHE_DIR/$sha/$key"
      if [ -f "$cache_path/index.html" ]; then
        echo "build-versions: cache hit for $tag@$sha -> $key"
        rm -rf "$out_dir"
        mkdir -p "$out_dir"
        cp -R "$cache_path/." "$out_dir/"
        copy_switcher "$key"
        continue
      fi
    fi
  fi

  echo "build-versions: cloning $tag -> $BUILD_DIR/$key"
  rm -rf "${BUILD_DIR:?}/$key"
  git -c advice.detachedHead=false clone --quiet --depth 1 -b "$tag" "$REPO_URL" "$BUILD_DIR/$key"

  echo "build-versions: building $key"
  (
    cd "$BUILD_DIR/$key"
    # shellcheck disable=SC2030  # subshell-scoped on purpose
    export SITE_VERSION_KEY="$key"
    export SITE_BASE
    export DIST_DIR
    eval "$INSTALL_CMD"
    eval "$BUILD_CMD"
  )

  copy_switcher "$key"

  if [ -n "$CACHE_DIR" ] && [ -n "${sha:-}" ] && [ -d "$out_dir" ]; then
    cache_path="$CACHE_DIR/$sha/$key"
    rm -rf "$cache_path"
    mkdir -p "$cache_path"
    cp -R "$out_dir/." "$cache_path/"
    echo "build-versions: cached $tag@$sha -> $cache_path"
  fi
done < <(jq -rc '.[] | @base64' "$DEPLOY_VERSIONS")

# 3. Build HEAD as `$NEXT_KEY` into the same $DIST_DIR. HEAD always rebuilds
#    (no cache lookup) since master is the moving tip.
echo "build-versions: building HEAD as $NEXT_KEY"
(
  cd "$WRKDIR"
  # shellcheck disable=SC2031  # subshell-scoped on purpose
  export SITE_VERSION_KEY="$NEXT_KEY"
  export SITE_BASE
  export DIST_DIR
  eval "$BUILD_CMD"
)
copy_switcher "$NEXT_KEY"

# 4. Publish the canonical (merged) versions.json so runtime/hybrid switcher
#    shims in any version can fetch ../versions.json and discover the full
#    list, including versions added after their own build was cached.
cp "$MERGED_MANIFEST" "$canonical_prefix/versions.json"
echo "build-versions: canonical manifest at $canonical_prefix/versions.json"

echo "build-versions: done. output in $DIST_DIR"
