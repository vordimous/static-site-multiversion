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
#   DIST_DIR            shared output directory        (default: $PWD/dist)
#   BUILD_DIR           where historical clones land   (default: a temp dir,
#                                                       removed on exit)
#   SITE_BASE           URL path prefix, if any        (default: empty)
#   INSTALL_CMD         install command per version    (default: pnpm install)
#   BUILD_CMD           build command per version      (default: pnpm build)
#   NEXT_KEY            version key for HEAD           (default: next)
#   NEXT_LABEL          dropdown label for HEAD        (default: $NEXT_KEY)
#   SWITCHER_JS         path to switcher.js to copy
#                       into each per-version output;
#                       set to empty to disable        (default: $script_dir/switcher.js)
#   CACHE_DIR           SHA-keyed artifact cache root  (default: empty = disabled)
#
# INSTALL_CMD and BUILD_CMD are passed through `eval`, so they accept full
# shell syntax (pipes, &&, subshells). Quote anything that needs to survive
# expansion at the call site. They run with cwd=$BUILD_DIR/<key>/ for
# historical clones (the clone's repo root) and cwd=$PWD for the HEAD build,
# so site-relative paths resolve consistently against each version's source.
#
# Builder contract: each build must honor SITE_VERSION_KEY and DIST_DIR (and
# SITE_BASE when set), writing output to:
#   $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/
# A build that leaves no index.html there fails the run.
#
# Versioning model:
#   - Each version's source `versions.json` (e.g. src/versions.json) is the
#     "seed" snapshot of versions known at build time. The orchestrator never
#     reads or rewrites it; historical clones keep their committed seed.
#   - After all per-version builds, the orchestrator writes the canonical
#     list (deploy-versions + a HEAD entry) to $DIST_DIR/[$SITE_BASE/]versions.json.
#     Switcher shims (scripts/switcher.js mode=runtime|hybrid) fetch it to
#     discover newer versions added after their own build.
#   - SWITCHER_JS, if set, is copied into every per-version output dir
#     so each version's <script src="./switcher.js"> resolves locally.

set -euo pipefail

: "${REPO_URL:?REPO_URL is required}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

DEPLOY_VERSIONS="${DEPLOY_VERSIONS:-deploy-versions.json}"
DIST_DIR="${DIST_DIR:-$PWD/dist}"
BUILD_DIR="${BUILD_DIR:-}"
SITE_BASE="${SITE_BASE:-}"
INSTALL_CMD="${INSTALL_CMD:-pnpm install}"
BUILD_CMD="${BUILD_CMD:-pnpm build}"
NEXT_KEY="${NEXT_KEY:-next}"
NEXT_LABEL="${NEXT_LABEL:-$NEXT_KEY}"
SWITCHER_JS="${SWITCHER_JS-$SCRIPT_DIR/switcher.js}"
CACHE_DIR="${CACHE_DIR:-}"

die() {
  echo "build-versions: $*" >&2
  exit 1
}

[ -f "$DEPLOY_VERSIONS" ] || die "$DEPLOY_VERSIONS not found"

# Keys and SITE_BASE segments become directory names that get `rm -rf`d, so
# anything that could resolve outside $DIST_DIR or $BUILD_DIR (".", "..",
# absolute paths, empty segments) is rejected before any filesystem work.
# Keep SEGMENT_RE in sync with schemas/deploy-versions.schema.json.
SEGMENT_RE='[A-Za-z0-9][A-Za-z0-9._-]*'

[[ "$NEXT_KEY" =~ ^${SEGMENT_RE}$ ]] || die "NEXT_KEY '$NEXT_KEY' must match ^${SEGMENT_RE}\$"

if [ -n "$SITE_BASE" ] && ! [[ "$SITE_BASE" =~ ^${SEGMENT_RE}(/${SEGMENT_RE})*$ ]]; then
  die "SITE_BASE '$SITE_BASE' must be one or more '/'-separated segments matching ^${SEGMENT_RE}\$"
fi

manifest_errors="$(jq -r --arg re "^${SEGMENT_RE}\$" --arg next "$NEXT_KEY" '
  if type != "array" then "top level must be an array"
  else
    (to_entries[] | .key as $i | .value
      | if type != "object" then "entry \($i): must be an object"
        elif (.key | type) != "string" or (.key | test($re) | not) then "entry \($i): key \(.key | tojson) must match \($re)"
        elif (.ref | type) != "string" or .ref == "" then "entry \($i): ref must be a non-empty string"
        elif .key == $next then "entry \($i): key \(.key | tojson) is reserved for the HEAD build (NEXT_KEY)"
        else empty end),
    ([.[] | objects | .key | strings] | group_by(.) | .[] | select(length > 1) | "duplicate key \(.[0] | tojson)")
  end
' "$DEPLOY_VERSIONS")" || die "$DEPLOY_VERSIONS is not valid JSON"

if [ -n "$manifest_errors" ]; then
  while IFS= read -r err; do
    echo "build-versions: $DEPLOY_VERSIONS: $err" >&2
  done <<< "$manifest_errors"
  exit 1
fi

OWNED_BUILD_DIR=""
if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR="$(mktemp -d -t ssm-build.XXXXXX)"
  OWNED_BUILD_DIR="$BUILD_DIR"
fi

MERGED_MANIFEST="$(mktemp -t merged-versions.XXXXXX)"
trap 'rm -rf "$MERGED_MANIFEST" ${OWNED_BUILD_DIR:+"$OWNED_BUILD_DIR"}' EXIT

mkdir -p "$DIST_DIR" "$BUILD_DIR"

# Per-builder output root: $DIST_DIR/[$SITE_BASE/]. Every per-version dir
# and the canonical versions.json land directly under this path.
output_root="$DIST_DIR"
if [ -n "$SITE_BASE" ]; then
  output_root="$output_root/$SITE_BASE"
fi
mkdir -p "$output_root"

# Resolves the per-key output dir under the output root.
key_outdir() { printf '%s/%s' "$output_root" "$1"; }

# Fails the run when a build exits 0 but wrote nothing where the contract
# says it should, e.g. a tag cut before the builder honored DIST_DIR.
require_output() {
  local key="$1" ref="$2" out
  out="$(key_outdir "$key")"
  [ -f "$out/index.html" ] || die "build of '$key' ($ref) wrote no $out/index.html. The builder must honor SITE_VERSION_KEY and DIST_DIR (and SITE_BASE when set)."
}

# 1. Compose the canonical manifest. This is the list switcher shims fetch
#    at runtime, so it lists every navigable version: deploy-versions.json
#    entries (the historical tags/branches) plus a `next` entry for HEAD.
#    Per-site seed files are not merged in: a seed is the page's own
#    per-build snapshot and typically holds a non-navigable self-reference
#    such as "current".
NEXT_ENTRY="$(jq -nc --arg k "$NEXT_KEY" --arg l "$NEXT_LABEL" '[{ key: $k, label: $l }]')"
jq -s '.[0] + .[1]' "$DEPLOY_VERSIONS" <(printf '%s' "$NEXT_ENTRY") > "$MERGED_MANIFEST"

echo "build-versions: canonical manifest composed (deploy-versions + $NEXT_KEY)"

# Resolves a tag (or branch) into the SHA of the commit it points to inside
# the source repo. For annotated tags `git ls-remote` returns two refs:
# `refs/tags/X` (the tag-object SHA) and `refs/tags/X^{}` (the commit it
# points at). The build clones at the commit, so the cache must key on the
# commit SHA, not the tag-object SHA. Try the peeled ref first; if empty
# (lightweight tag, no peel exists), fall back to the plain ref or a branch.
resolve_sha() {
  local sha
  sha="$(git ls-remote "$REPO_URL" "refs/tags/$1^{}" 2>/dev/null | awk 'NR==1{print $1}')"
  if [ -z "$sha" ]; then
    sha="$(git ls-remote "$REPO_URL" "refs/tags/$1" "refs/heads/$1" 2>/dev/null | awk 'NR==1{print $1}')"
  fi
  printf '%s' "$sha"
}

# Drops a switcher.js into the per-version output dir, when configured.
copy_switcher() {
  local key="$1" out
  out="$(key_outdir "$key")"
  if [ -n "$SWITCHER_JS" ] && [ -f "$SWITCHER_JS" ]; then
    cp "$SWITCHER_JS" "$out/switcher.js"
  fi
}

# Injects the bolted version-switcher mount into HTML files in the
# per-version output that don't already have a dropdown of their own.
# Lets historical builds (whose source commits predate the integration)
# still ship a working dropdown without rewriting tags.
inject_mount() {
  local key="$1" out url_base
  out="$(key_outdir "$key")"
  if [ -n "$SITE_BASE" ]; then
    url_base="/$SITE_BASE/$key"
  else
    url_base="/$key"
  fi
  if [ -x "$SCRIPT_DIR/inject-mount.sh" ]; then
    "$SCRIPT_DIR/inject-mount.sh" "$out" "$url_base" || true
  fi
}

# 2. Build each historical version into the shared $DIST_DIR. If $CACHE_DIR is
#    configured and we have a SHA match for the tag, restore the cached output
#    instead of cloning + rebuilding.
WRKDIR="$PWD"

while IFS= read -r row; do
  key=$(echo "$row" | base64 --decode | jq -r '.key')
  ref=$(echo "$row" | base64 --decode | jq -r '.ref')

  out_dir="$(key_outdir "$key")"
  sha=""

  if [ -n "$CACHE_DIR" ]; then
    sha="$(resolve_sha "$ref")"
    if [ -n "$sha" ]; then
      cache_path="$CACHE_DIR/$sha/$key"
      if [ -f "$cache_path/index.html" ]; then
        echo "build-versions: cache hit for $ref@$sha -> $key"
        rm -rf "$out_dir"
        mkdir -p "$out_dir"
        cp -R "$cache_path/." "$out_dir/"
        copy_switcher "$key"
        inject_mount "$key"
        continue
      fi
    fi
  fi

  echo "build-versions: cloning $ref -> $BUILD_DIR/$key"
  rm -rf "${BUILD_DIR:?}/$key"
  git -c advice.detachedHead=false clone --quiet --depth 1 -b "$ref" "$REPO_URL" "$BUILD_DIR/$key"

  echo "build-versions: building $key"
  rm -rf "$out_dir"
  (
    cd "$BUILD_DIR/$key"
    # shellcheck disable=SC2030  # subshell-scoped on purpose
    export SITE_VERSION_KEY="$key"
    export SITE_BASE
    export DIST_DIR
    # Build-time configs (e.g. baked-mode navbar dropdowns in VuePress /
    # Docusaurus) read the version list from here. Each clone uses its own
    # ./deploy-versions.json from the tag.
    # shellcheck disable=SC2030  # subshell-scoped on purpose
    export DEPLOY_VERSIONS="$BUILD_DIR/$key/deploy-versions.json"
    eval "$INSTALL_CMD"
    eval "$BUILD_CMD"
  )
  require_output "$key" "$ref"

  copy_switcher "$key"
  inject_mount "$key"

  if [ -n "$sha" ]; then
    cache_path="$CACHE_DIR/$sha/$key"
    rm -rf "$cache_path"
    mkdir -p "$cache_path"
    cp -R "$out_dir/." "$cache_path/"
    echo "build-versions: cached $ref@$sha -> $cache_path"
  fi
# Each entry is base64-encoded by jq so a newline inside any field can't
# split the row across two iterations of the read loop.
done < <(jq -rc '.[] | @base64' "$DEPLOY_VERSIONS")

# 3. Build HEAD as `$NEXT_KEY` into the same $DIST_DIR. HEAD always rebuilds
#    (no cache lookup) since master is the moving tip.
echo "build-versions: building HEAD as $NEXT_KEY"
# shellcheck disable=SC2031  # reads the orchestrator-scope value, before any historical-loop subshell ran
HEAD_DEPLOY_VERSIONS="$DEPLOY_VERSIONS"
rm -rf "$(key_outdir "$NEXT_KEY")"
(
  cd "$WRKDIR"
  # shellcheck disable=SC2031  # subshell-scoped on purpose
  export SITE_VERSION_KEY="$NEXT_KEY"
  export SITE_BASE
  export DIST_DIR
  # Same DEPLOY_VERSIONS export as the historical builds. For HEAD this is
  # the input deploy-versions path passed to the orchestrator.
  # shellcheck disable=SC2031  # subshell-scoped on purpose
  export DEPLOY_VERSIONS="$HEAD_DEPLOY_VERSIONS"
  eval "$BUILD_CMD"
)
require_output "$NEXT_KEY" HEAD
copy_switcher "$NEXT_KEY"
inject_mount "$NEXT_KEY"

# 4. Publish the canonical (merged) versions.json so runtime/hybrid switcher
#    shims in any version can fetch ../versions.json and discover the full
#    list, including versions added after their own build was cached. chmod
#    explicitly because mktemp's 600 default would otherwise propagate
#    through cp and nginx (running as a non-root user) would 403 the file.
cp "$MERGED_MANIFEST" "$output_root/versions.json"
chmod 644 "$output_root/versions.json"
echo "build-versions: canonical manifest at $output_root/versions.json"

echo "build-versions: done. output in $DIST_DIR"
