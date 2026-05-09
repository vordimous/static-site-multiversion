# Plain HTML example

This is the contract, distilled. The build is `cp`. Every other example in this repo is a real generator doing the same thing under more layers.

## How the contract is wired

There is no generator config to map env vars onto. [`build.sh`](build.sh) reads the contract directly:

```bash
#!/usr/bin/env bash
set -euo pipefail
: "${SITE_VERSION_KEY:?SITE_VERSION_KEY is required}"
: "${DIST_DIR:?DIST_DIR is required}"

out="$DIST_DIR"
if [ -n "${SITE_BASE:-}" ]; then
  out="$out/$SITE_BASE"
fi
out="$out/$SITE_VERSION_KEY"

mkdir -p "$out"
cp -R src/. "$out/"
```

That's the whole build. The orchestrator places the merged `versions.json` at `src/versions.json` before this runs (default `VERSIONS_MANIFEST` path), and the `cp -R` copies it into the output along with the HTML.

## The one caveat: client-side JS for the switcher

A real SSG can read `versions.json` at build time and inline the dropdown into the HTML. With no build step, the switcher has to run in the browser. [`src/switcher.js`](src/switcher.js) fetches `./versions.json` (deployed alongside the page), parses it, and renders a `<select>` that swaps the version segment in the URL on change. Each page reserves a `<div id="version-switcher">` slot and loads the script with `defer`.

This is the only honest cost of "no generator." If you want the switcher inlined at build time, swap `cp` for a templating step (sed, awk, or a 20-line Python script) and you've reinvented the smallest possible SSG.

## Running locally

```bash
SITE_VERSION_KEY=next DIST_DIR=$(pwd)/../../dist ./build.sh
```

Output is at `../../dist/next/`. Serve it with anything (`python3 -m http.server`, `npx serve`, etc.) and open `/next/`.

## Multi-version build

Pass through to the orchestrator:

```bash
INSTALL_CMD="true" \
BUILD_CMD="./build.sh" \
  scripts/build-versions.sh
```

(`INSTALL_CMD="true"` because there are no dependencies to install.)
