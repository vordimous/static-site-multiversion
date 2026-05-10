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

That's the whole build. Each clone keeps its own committed `src/versions.json` seed (the snapshot of versions known at build time), and the `cp -R` copies it into the output along with the HTML. After every per-version build, the orchestrator publishes the canonical merged `versions.json` (deploy-versions plus a `next` entry) at `$DIST_DIR/[$SITE_BASE/]versions.json` for the runtime/hybrid switcher to fetch.

## The one caveat: client-side JS for the switcher

A real SSG can read `versions.json` at build time and inline the dropdown into the HTML. With no build step, the switcher has to run in the browser. The shared shim at [`scripts/switcher.js`](../../scripts/switcher.js) fetches `./versions.json` (deployed alongside the page), parses it, and renders a `<select>` that swaps the version segment in the URL on change. Each page reserves a `<div id="version-switcher">` slot and loads the script with `defer`. The orchestrator copies `scripts/switcher.js` into every per-version output dir, so the per-page `<script src="./switcher.js">` resolves locally — no per-example asset wiring required.

This is the only honest cost of "no generator." If you want the switcher inlined at build time, swap `cp` for a templating step (sed, awk, or a 20-line Python script) and you've reinvented the smallest possible SSG.

## Running locally

```bash
SITE_VERSION_KEY=next DIST_DIR=$(pwd)/../../dist ./build.sh
```

Output is at `../../dist/next/`. Standalone `build.sh` runs without the orchestrator, so `switcher.js` won't be in the output — the page will render without a working dropdown until you serve it via the multi-version build below (or copy `../../scripts/switcher.js` into the output yourself). Serve it with anything (`python3 -m http.server`, `npx serve`, etc.) and open `/next/`.

## Multi-version build

Pass through to the orchestrator:

```bash
INSTALL_CMD="true" \
BUILD_CMD="./build.sh" \
  scripts/build-versions.sh
```

(`INSTALL_CMD="true"` because there are no dependencies to install.)
