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
#   scripts/demo-all.sh                # all examples
#   scripts/demo-all.sh plain-html     # one example
#   scripts/demo-all.sh plain-html hugo

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

DEPLOY_VERSIONS_FILE="$REPO_ROOT/deploy-versions.demo.json"
ORCHESTRATOR="$REPO_ROOT/scripts/build-versions.sh"
REPO_URL="file://$REPO_ROOT"
SERVE_ROOT="$REPO_ROOT/.demo/_serve"

[ -f "$DEPLOY_VERSIONS_FILE" ] || { echo "demo-all: $DEPLOY_VERSIONS_FILE not found" >&2; exit 1; }
[ -x "$ORCHESTRATOR" ]         || { echo "demo-all: $ORCHESTRATOR not executable" >&2; exit 1; }

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
  jq -c '.[]' "$merged_deploy" | while IFS= read -r entry; do
    local tag
    tag="$(printf '%s' "$entry" | jq -r '.tag')"
    if git -C "$REPO_ROOT" cat-file -e "${tag}:examples/${builder}" 2>/dev/null; then
      printf '%s\n' "$entry"
    else
      echo "demo-all: $builder: dropping ref '$tag' (examples/$builder/ missing at that ref)" >&2
    fi
  done | jq -s '.' > "$filtered_deploy"
  mv "$filtered_deploy" "$merged_deploy"

  # The orchestrator overwrites $manifest in-place during the HEAD build so
  # generators read the merged switcher list. Snapshot and restore so re-runs
  # don't dirty the working tree (and don't accumulate duplicate entries on
  # subsequent runs, since the merge is concat-only).
  local manifest_backup
  manifest_backup="$(mktemp)"
  cp "$REPO_ROOT/$manifest" "$manifest_backup"

  local rc=0
  DEPLOY_VERSIONS="$merged_deploy" \
  VERSIONS_MANIFEST="$manifest" \
  REPO_URL="$REPO_URL" \
  INSTALL_CMD="$install_cmd" \
  BUILD_CMD="$build_cmd" \
  DIST_DIR="$SERVE_ROOT" \
  BUILD_DIR="$build_root" \
  SITE_BASE="$builder" \
    "$ORCHESTRATOR" || rc=$?

  cp "$manifest_backup" "$REPO_ROOT/$manifest"
  rm -f "$manifest_backup" "$merged_deploy" "$REPO_ROOT/versions.json"

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

# Top-level landing page that links into each built builder.
write_index() {
  local out="$SERVE_ROOT/index.html"
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
      [ -d "$SERVE_ROOT/$b" ] || continue
      printf '      <tr><td><strong>%s</strong></td><td>' "$b"
      for k in 0.9 1.0 unstable next; do
        if [ -d "$SERVE_ROOT/$b/$k" ]; then
          printf '<a href="./%s/%s/">%s</a> ' "$b" "$k" "$k"
        fi
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

write_index

echo
echo "=== summary ==="
printf 'ran:     %s\n' "${RAN[*]:-(none)}"
printf 'skipped: %s\n' "${SKIPPED[*]:-(none)}"
printf 'failed:  %s\n' "${FAILED[*]:-(none)}"
echo "docroot: $SERVE_ROOT"

[ "${#FAILED[@]}" -eq 0 ]
