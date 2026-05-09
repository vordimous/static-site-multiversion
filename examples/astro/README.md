# Astro example

A minimal Astro 4 site that honors the [static-site-multiversion](../../README.md) builder contract.

## How the contract is wired

| Env var | Astro option | Meaning |
| --- | --- | --- |
| `SITE_VERSION_KEY` | part of `outDir` and `base` | URL slug for this version |
| `SITE_BASE` | part of `outDir` and `base` | optional path prefix |
| `DIST_DIR` | base of `outDir` | shared output root across versions |

Astro writes flat to `outDir`, so the config combines the env vars into:

```
outDir = $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/
base   = /[$SITE_BASE/]$SITE_VERSION_KEY/
```

See [astro.config.mjs](astro.config.mjs) for the wiring.

## Running locally

```bash
npm install
SITE_VERSION_KEY=next npm run build
```

Output is at `../../dist/next/`.
