# Hugo example

A minimal Hugo site that honors the [static-site-multiversion](../../README.md) builder contract.

This example demonstrates the contract working in a third runtime (Go) on top of Node and Python — the orchestrator script is unchanged; only the example's wrapper differs.

## How the contract is wired

Hugo accepts both `--baseURL` and `--destination` as CLI flags, so a thin shell wrapper ([build.sh](build.sh)) maps the env vars onto them:

| Env var | Hugo CLI flag | Meaning |
| --- | --- | --- |
| `SITE_VERSION_KEY` | part of `--baseURL` and `--destination` | URL slug for this version |
| `SITE_BASE` | part of `--baseURL` and `--destination` | optional path prefix |
| `DIST_DIR` | base of `--destination` | shared output root |

Output lands at:

```
$DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/
```

## Running locally

Hugo is a single binary. Install via Homebrew (`brew install hugo`), Scoop, or [download a release](https://github.com/gohugoio/hugo/releases).

```bash
SITE_VERSION_KEY=next ./build.sh
```

Output is at `../../dist/next/`. No `npm install` step needed — Hugo has no JS dependencies.

## Version switcher

Hugo wires the shared client-side switcher: each page mounts `<div id="version-switcher" data-mode="hybrid">` with an inline seed and references `./switcher.js`. The orchestrator copies [`scripts/switcher.js`](../../scripts/switcher.js) into every per-version output directory, and the hybrid mode renders the seed first then fetches the canonical `versions.json` to pick up newer releases without rebuilding old versions.

## Multi-version build

Pass through to the orchestrator with the right command:

```bash
INSTALL_CMD="true" \
BUILD_CMD="./build.sh" \
  scripts/build-versions.sh
```

(`INSTALL_CMD="true"` because Hugo doesn't need an install step per version.)
