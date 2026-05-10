# Docusaurus example

A minimal Docusaurus 3 site (classic preset) that honors the [static-site-multiversion](../../README.md) builder contract.

## How the contract is wired

| Env var | Docusaurus knob | Meaning |
| --- | --- | --- |
| `SITE_VERSION_KEY` | part of `baseUrl` (in `docusaurus.config.js`) | URL slug for this version |
| `SITE_BASE` | part of `baseUrl` | optional path prefix |
| `DIST_DIR` | base of `--out-dir` (in `build.sh`) | shared output root |

`baseUrl` is computed from env at config evaluation. The output directory is passed as a CLI flag from a thin shell wrapper ([build.sh](build.sh)) because Docusaurus does not pick up the destination from env.

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

## Note on Docusaurus's own versioning feature

Docusaurus has a built-in versioning feature (`docs.versions`) that snapshots docs into per-version directories at build time. That solves a different problem: keeping all versions in **one** repo. This contract is for keeping each version in **its own git tag** and merging them at deploy time. The two approaches are complementary, not redundant.
