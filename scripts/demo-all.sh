#!/usr/bin/env bash
#
# Builds each examples/<builder>/ as its own multi-version demo against this
# repo's own demo-* tags and branch (see deploy-versions.demo.json). Treats
# this repo itself as the consumer site: REPO_URL is a file:// pointer to
# $REPO_ROOT, and historical clones land under .demo/<builder>/build/.
#
# Each builder is built with SITE_BASE=<builder> into a shared docroot at
# .demo/_serve/, so every builder can be hosted side-by-side under one
# server (see scripts/demo-serve.sh). URLs end up as /<builder>/<key>/...,
# matching the pattern used by .github/workflows/demos.yml in CI.
#
# Examples whose runtime toolchain (node / hugo / python+mkdocs) isn't
# available locally are skipped and reported, not failed.
#
# Usage:
#   scripts/demo-all.sh                       # all examples
#   scripts/demo-all.sh plain-html            # one example
#   scripts/demo-all.sh plain-html hugo
#   scripts/demo-all.sh --no-index plain-html # skip top-level index.html /
#                                             # versions.json (use when this
#                                             # is one of several parallel
#                                             # partial runs that will be
#                                             # merged later, e.g. CI matrix)

set -euo pipefail

WRITE_INDEX=1
ARGS=()
for a in "$@"; do
  case "$a" in
    --no-index) WRITE_INDEX=0 ;;
    *) ARGS+=("$a") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEPLOY_VERSIONS_FILE="$REPO_ROOT/deploy-versions.demo.json"
ORCHESTRATOR="$REPO_ROOT/scripts/build-versions.sh"
REPO_URL="file://$REPO_ROOT"
SERVE_ROOT="$REPO_ROOT/.demo/_serve"
CACHE_DIR="${CACHE_DIR:-$REPO_ROOT/.cache}"

# Optional outer URL prefix that all builders nest under. Required for
# project-style GitHub Pages deploys served at /<repo>/, where every link,
# asset, and fetch URL needs to start with /<repo>/. When set, SITE_BASE
# becomes "<prefix>/<builder>" and everything (per-builder dirs, the
# landing page, the cross-builder index) lives under .demo/_serve/<prefix>/.
# Leave empty for local serving where the docroot maps to "/".
SITE_BASE_PREFIX="${SITE_BASE_PREFIX:-}"
PUBLISH_ROOT="$SERVE_ROOT"
if [ -n "$SITE_BASE_PREFIX" ]; then
  PUBLISH_ROOT="$SERVE_ROOT/$SITE_BASE_PREFIX"
fi

# Per-iteration mktemp files are tracked here so the EXIT trap reaps them
# even on early failures, instead of relying on the OS to clean up.
DEMO_TMPFILES=()
cleanup_tmpfiles() {
  if [ "${#DEMO_TMPFILES[@]}" -gt 0 ]; then
    rm -f "${DEMO_TMPFILES[@]}"
  fi
}
trap cleanup_tmpfiles EXIT

[ -f "$DEPLOY_VERSIONS_FILE" ] || { echo "demo-all: $DEPLOY_VERSIONS_FILE not found" >&2; exit 1; }
[ -x "$ORCHESTRATOR" ]         || { echo "demo-all: $ORCHESTRATOR not executable" >&2; exit 1; }

mkdir -p "$CACHE_DIR"

ALL_BUILDERS=(plain-html vuepress vitepress astro docusaurus eleventy hugo mkdocs)

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=("${ALL_BUILDERS[@]}")
fi

# Wipe the shared docroot once at the start; each builder appends to it.
# Clear contents in place rather than rm -rf-ing the dir so an attached
# nginx bind mount (scripts/demo-serve.sh) doesn't lose its inode.
mkdir -p "$SERVE_ROOT"
find "$SERVE_ROOT" -mindepth 1 -delete
mkdir -p "$PUBLISH_ROOT"

RAN=()
SKIPPED=()
FAILED=()

run_builder() {
  local builder="$1" install_cmd="$2" build_cmd="$3" manifest="$4"
  local build_root="$REPO_ROOT/.demo/$builder/build"
  local per_example="$REPO_ROOT/examples/$builder/deploy-versions.json"

  rm -rf "$REPO_ROOT/.demo/$builder/build"
  mkdir -p "$build_root"

  echo
  echo "=== demo: $builder ==="

  # Merge the global demo refs with this builder's own deploy-versions so
  # both axes (repo-wide demo timeline + per-builder generator versions)
  # show up in the version switcher. If a builder has no per-example file
  # the global axis is used directly.
  local merged_deploy
  merged_deploy="$(mktemp)"
  DEMO_TMPFILES+=("$merged_deploy")
  if [ -f "$per_example" ]; then
    jq -s '.[0] + .[1]' "$DEPLOY_VERSIONS_FILE" "$per_example" > "$merged_deploy"
  else
    cp "$DEPLOY_VERSIONS_FILE" "$merged_deploy"
  fi

  # Drop refs that don't actually contain examples/<builder>/. Lets newer
  # builders (added after the global demo-* tags were cut) coexist with the
  # global axis without failing the historical builds.
  local filtered_deploy
  filtered_deploy="$(mktemp)"
  DEMO_TMPFILES+=("$filtered_deploy")
  jq -c '.[]' "$merged_deploy" | while IFS= read -r entry; do
    local ref
    ref="$(printf '%s' "$entry" | jq -r '.ref')"
    if git -C "$REPO_ROOT" cat-file -e "${ref}:examples/${builder}" 2>/dev/null; then
      printf '%s\n' "$entry"
    else
      echo "demo-all: $builder: dropping ref '$ref' (examples/$builder/ missing at that ref)" >&2
    fi
  done | jq -s '.' > "$filtered_deploy"
  mv "$filtered_deploy" "$merged_deploy"

  # The orchestrator runs INSTALL_CMD only inside historical clones, not
  # for the HEAD build, so we run it once locally first so the HEAD build
  # has its own node_modules. Idempotent for already-installed lockfiles.
  if [ "$install_cmd" != "true" ]; then
    ( cd "$REPO_ROOT" && eval "$install_cmd" )
  fi

  local rc=0
  local site_base="$builder"
  if [ -n "$SITE_BASE_PREFIX" ]; then
    site_base="$SITE_BASE_PREFIX/$builder"
  fi

  DEPLOY_VERSIONS="$merged_deploy" \
  VERSIONS_MANIFEST="$manifest" \
  REPO_URL="$REPO_URL" \
  INSTALL_CMD="$install_cmd" \
  BUILD_CMD="$build_cmd" \
  DIST_DIR="$SERVE_ROOT" \
  BUILD_DIR="$build_root" \
  SITE_BASE="$site_base" \
  CACHE_DIR="$CACHE_DIR/$builder" \
    "$ORCHESTRATOR" || rc=$?

  rm -f "$merged_deploy"

  if [ "$rc" -eq 0 ]; then
    RAN+=("$builder")
  else
    FAILED+=("$builder")
  fi
}

skip_builder() {
  local builder="$1" reason="$2"
  echo
  echo "=== skip: $builder ($reason) ==="
  SKIPPED+=("$builder ($reason)")
}

dispatch() {
  local builder="$1"
  case "$builder" in
    plain-html)
      run_builder plain-html \
        "true" \
        "(cd examples/plain-html && ./build.sh)" \
        "examples/plain-html/src/versions.json"
      ;;
    vuepress)
      command -v node >/dev/null || { skip_builder vuepress "node not installed"; return; }
      run_builder vuepress \
        "(cd examples/vuepress && npm install --silent)" \
        "(cd examples/vuepress && npm run build)" \
        "examples/vuepress/src/versions.json"
      ;;
    vitepress)
      command -v node >/dev/null || { skip_builder vitepress "node not installed"; return; }
      run_builder vitepress \
        "(cd examples/vitepress && npm install --silent)" \
        "(cd examples/vitepress && npm run build)" \
        "examples/vitepress/src/versions.json"
      ;;
    astro)
      command -v node >/dev/null || { skip_builder astro "node not installed"; return; }
      run_builder astro \
        "(cd examples/astro && npm install --silent)" \
        "(cd examples/astro && npm run build)" \
        "examples/astro/src/versions.json"
      ;;
    docusaurus)
      command -v node >/dev/null || { skip_builder docusaurus "node not installed"; return; }
      run_builder docusaurus \
        "(cd examples/docusaurus && npm install --silent)" \
        "(cd examples/docusaurus && npm run build)" \
        "examples/docusaurus/src/versions.json"
      ;;
    eleventy)
      command -v node >/dev/null || { skip_builder eleventy "node not installed"; return; }
      run_builder eleventy \
        "(cd examples/eleventy && npm install --silent)" \
        "(cd examples/eleventy && npm run build)" \
        "examples/eleventy/src/versions.json"
      ;;
    hugo)
      command -v hugo >/dev/null || { skip_builder hugo "hugo not installed"; return; }
      run_builder hugo \
        "true" \
        "(cd examples/hugo && ./build.sh)" \
        "examples/hugo/versions.json"
      ;;
    mkdocs)
      command -v python3 >/dev/null || { skip_builder mkdocs "python3 not installed"; return; }
      if ! python3 -c 'import mkdocs' 2>/dev/null; then
        skip_builder mkdocs "mkdocs python package not installed (pip install -r examples/mkdocs/requirements.txt)"
        return
      fi
      run_builder mkdocs \
        "true" \
        "(cd examples/mkdocs && ./build.sh)" \
        "examples/mkdocs/versions.json"
      ;;
    *)
      skip_builder "$builder" "unknown builder"
      ;;
  esac
}

for b in "${TARGETS[@]}"; do
  dispatch "$b"
done

# Write the top-level landing page (index.html) and cross-builder
# versions.json by delegating to scripts/demo-index.sh. Skipped when
# --no-index is set, e.g. CI matrix shards that will be merged later.
if [ "$WRITE_INDEX" -eq 1 ]; then
  PUBLISH_ROOT="$PUBLISH_ROOT" SITE_BASE_PREFIX="$SITE_BASE_PREFIX" \
    "$REPO_ROOT/scripts/demo-index.sh"
fi

echo
echo "=== summary ==="
printf 'ran:     %s\n' "${RAN[*]:-(none)}"
printf 'skipped: %s\n' "${SKIPPED[*]:-(none)}"
printf 'failed:  %s\n' "${FAILED[*]:-(none)}"
echo "docroot: $SERVE_ROOT"

[ "${#FAILED[@]}" -eq 0 ]
