# VuePress example

A minimal VuePress 2 site that honors the [static-site-multiversion](../../README.md) builder contract.

## How the contract is wired

VuePress reads two configuration values that map onto our env vars:

| Env var | VuePress option | Meaning |
| --- | --- | --- |
| `SITE_VERSION_KEY` | part of `base` | URL slug for this version (e.g. `next`, `0.9`) |
| `SITE_BASE` | part of `base` | optional path prefix (e.g. `my-docs`) |
| `DIST_DIR` | `dest` | shared output root across all versions |

VuePress writes flat to `dest`, so the config combines the env vars into the per-version output path:

```
dest = $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/
base = /[$SITE_BASE/]$SITE_VERSION_KEY/
```

The `base` value is what makes asset URLs in the rendered HTML resolve correctly when deployed under the version path.

See [src/.vuepress/config.js](src/.vuepress/config.js) for the wiring.

## Running locally

Single-version build (just HEAD as `next`):

```bash
pnpm install
SITE_VERSION_KEY=next pnpm build
```

Output is at `../../dist/next/` relative to this example.

## Multi-version build

The orchestrator in `scripts/build-versions.sh` clones each historical tag, copies the merged `versions.json` into the clone, and invokes the build with `SITE_VERSION_KEY` set. To run it against a real repo whose deploy branch points at this example:

```bash
REPO_URL=https://github.com/you/your-site.git \
  INSTALL_CMD="pnpm install" \
  BUILD_CMD="pnpm build" \
  scripts/build-versions.sh
```
