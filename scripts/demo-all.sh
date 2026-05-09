#!/usr/bin/env bash
#
# Builds each examples/<builder>/ as its own multi-version demo against this
# repo's own demo-* tags and branch (see deploy-versions.demo.json). Treats
# this repo itself as the consumer site: REPO_URL is a file:// pointer to
# $REPO_ROOT, and historical clones land under .demo/<builder>/build/.
#
# Examples whose runtime toolchain (node / hugo / python+mkdocs) isn't
# available locally are skipped and reported, not failed.
#
# Output: .demo/<builder>/dist/<key>/ per built version. Serve any subtree to
# inspect the per-version output and the merged versions.json switcher.
#
# Usage:
#   scripts/demo-all.sh                # all examples
#   scripts/demo-all.sh plain-html     # one example
#   scripts/demo-all.sh plain-html hugo

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEPLOY_VERSIONS_FILE="$REPO_ROOT/deploy-versions.demo.json"
ORCHESTRATOR="$REPO_ROOT/scripts/build-versions.sh"
REPO_URL="file://$REPO_ROOT"

[ -f "$DEPLOY_VERSIONS_FILE" ] || { echo "demo-all: $DEPLOY_VERSIONS_FILE not found" >&2; exit 1; }
[ -x "$ORCHESTRATOR" ]         || { echo "demo-all: $ORCHESTRATOR not executable" >&2; exit 1; }

ALL_BUILDERS=(plain-html vuepress astro docusaurus eleventy hugo mkdocs)

if [ "$#" -gt 0 ]; then
  TARGETS=("$@")
else
  TARGETS=("${ALL_BUILDERS[@]}")
fi

RAN=()
SKIPPED=()
FAILED=()

run_builder() {
  local builder="$1" install_cmd="$2" build_cmd="$3" manifest="$4"
  local out_root="$REPO_ROOT/.demo/$builder"

  rm -rf "$out_root"
  mkdir -p "$out_root"

  echo
  echo "=== demo: $builder ==="

  if DEPLOY_VERSIONS="$DEPLOY_VERSIONS_FILE" \
     VERSIONS_MANIFEST="$manifest" \
     REPO_URL="$REPO_URL" \
     INSTALL_CMD="$install_cmd" \
     BUILD_CMD="$build_cmd" \
     DIST_DIR="$out_root/dist" \
     BUILD_DIR="$out_root/build" \
       "$ORCHESTRATOR"; then
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
        "cd examples/plain-html && ./build.sh" \
        "examples/plain-html/src/versions.json"
      ;;
    vuepress)
      command -v node >/dev/null || { skip_builder vuepress "node not installed"; return; }
      run_builder vuepress \
        "cd examples/vuepress && npm install --silent" \
        "cd examples/vuepress && npm run build" \
        "examples/vuepress/src/versions.json"
      ;;
    astro)
      command -v node >/dev/null || { skip_builder astro "node not installed"; return; }
      run_builder astro \
        "cd examples/astro && npm install --silent" \
        "cd examples/astro && npm run build" \
        "examples/astro/src/versions.json"
      ;;
    docusaurus)
      command -v node >/dev/null || { skip_builder docusaurus "node not installed"; return; }
      run_builder docusaurus \
        "cd examples/docusaurus && npm install --silent" \
        "cd examples/docusaurus && npm run build" \
        "examples/docusaurus/src/versions.json"
      ;;
    eleventy)
      command -v node >/dev/null || { skip_builder eleventy "node not installed"; return; }
      run_builder eleventy \
        "cd examples/eleventy && npm install --silent" \
        "cd examples/eleventy && npm run build" \
        "examples/eleventy/src/versions.json"
      ;;
    hugo)
      command -v hugo >/dev/null || { skip_builder hugo "hugo not installed"; return; }
      run_builder hugo \
        "true" \
        "cd examples/hugo && ./build.sh" \
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
        "cd examples/mkdocs && ./build.sh" \
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

echo
echo "=== summary ==="
printf 'ran:     %s\n' "${RAN[*]:-(none)}"
printf 'skipped: %s\n' "${SKIPPED[*]:-(none)}"
printf 'failed:  %s\n' "${FAILED[*]:-(none)}"

[ "${#FAILED[@]}" -eq 0 ]
