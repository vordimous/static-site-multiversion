# Eleventy example

A minimal Eleventy 3 site that honors the [static-site-multiversion](../../README.md) builder contract.

This is the lightest-weight Node example — Eleventy supports the contract natively, no shell wrapper required.

## How the contract is wired

| Env var | Eleventy option | Meaning |
| --- | --- | --- |
| `SITE_VERSION_KEY` | part of `pathPrefix` and `dir.output` | URL slug for this version |
| `SITE_BASE` | part of `pathPrefix` and `dir.output` | optional path prefix |
| `DIST_DIR` | base of `dir.output` | shared output root |

The config in [eleventy.config.js](eleventy.config.js) reads env directly and computes both values.

In templates, use the built-in `url` filter (e.g. `{{ "/guide/" | url }}`) so internal links automatically pick up `pathPrefix`. That keeps content portable across versions.

Output lands at:

```
$DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/
```

## Running locally

```bash
npm install
SITE_VERSION_KEY=next npm run build
```

Output is at `../../dist/next/`.

## Multi-version build

When invoking the orchestrator against a real consumer repo whose deploy branch points at this example:

```bash
REPO_URL=https://github.com/you/your-site.git \
  INSTALL_CMD="npm install" \
  BUILD_CMD="npm run build" \
  scripts/build-versions.sh
```
