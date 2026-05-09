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
#
# INSTALL_CMD and BUILD_CMD are passed through `eval`, so they accept full
# shell syntax (pipes, &&, subshells). Quote anything that needs to survive
# expansion at the call site.
#
# Builder contract: each build must honor SITE_VERSION_KEY and DIST_DIR (and
# SITE_BASE when set), writing output to:
#   $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/

set -euo pipefail

: "${REPO_URL:?REPO_URL is required}"

DEPLOY_VERSIONS="${DEPLOY_VERSIONS:-deploy-versions.json}"
VERSIONS_MANIFEST="${VERSIONS_MANIFEST:-src/versions.json}"
DIST_DIR="${DIST_DIR:-$PWD/dist}"
BUILD_DIR="${BUILD_DIR:-$PWD/build}"
SITE_BASE="${SITE_BASE:-}"
INSTALL_CMD="${INSTALL_CMD:-pnpm install}"
BUILD_CMD="${BUILD_CMD:-pnpm build}"
NEXT_KEY="${NEXT_KEY:-next}"

if [ ! -f "$DEPLOY_VERSIONS" ]; then
  echo "build-versions: $DEPLOY_VERSIONS not found" >&2
  exit 1
fi

if [ ! -f "$VERSIONS_MANIFEST" ]; then
  echo "build-versions: $VERSIONS_MANIFEST not found" >&2
  exit 1
fi

mkdir -p "$DIST_DIR" "$BUILD_DIR"

# 1. Build a unified versions manifest by merging the site's own list with
#    deploy-versions.json. Each historical clone gets this same manifest copied
#    in before it builds, so every version's UI shows the same switcher.
MERGED_MANIFEST="$PWD/versions.json"
jq -s '.[0] + .[1]' "$VERSIONS_MANIFEST" "$DEPLOY_VERSIONS" > "$MERGED_MANIFEST"

echo "build-versions: merged manifest written to $MERGED_MANIFEST"

# 2. Build each historical version into the shared $DIST_DIR.
WRKDIR="$PWD"

while IFS= read -r row; do
  key=$(echo "$row" | base64 --decode | jq -r '.key')
  tag=$(echo "$row" | base64 --decode | jq -r '.tag')

  echo "build-versions: cloning $tag -> $BUILD_DIR/$key"
  rm -rf "${BUILD_DIR:?}/$key"
  git -c advice.detachedHead=false clone --quiet --depth 1 -b "$tag" "$REPO_URL" "$BUILD_DIR/$key"

  cp "$MERGED_MANIFEST" "$BUILD_DIR/$key/$VERSIONS_MANIFEST"

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
done < <(jq -rc '.[] | @base64' "$DEPLOY_VERSIONS")

# 3. Build HEAD as `$NEXT_KEY` into the same $DIST_DIR.
echo "build-versions: building HEAD as $NEXT_KEY"
cp "$MERGED_MANIFEST" "$VERSIONS_MANIFEST"
(
  cd "$WRKDIR"
  # shellcheck disable=SC2031  # subshell-scoped on purpose
  export SITE_VERSION_KEY="$NEXT_KEY"
  export SITE_BASE
  export DIST_DIR
  eval "$BUILD_CMD"
)

echo "build-versions: done. output in $DIST_DIR"
