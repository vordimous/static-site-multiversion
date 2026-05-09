# VitePress example

A minimal VitePress 1.x site that honors the [static-site-multiversion](../../README.md) builder contract.

## How the contract is wired

[`src/.vitepress/config.mjs`](src/.vitepress/config.mjs) reads three environment variables and translates them into VitePress config:

| Env var            | VitePress option | Effect                                          |
| ------------------ | ---------------- | ----------------------------------------------- |
| `SITE_VERSION_KEY` | `base`           | URL path prefix becomes `/[$SITE_BASE/]$KEY/`   |
| `SITE_BASE`        | `base`           | Optional outer prefix; combined with the key    |
| `DIST_DIR`         | `outDir`         | Absolute build output root                      |

The output lands at `$DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/`, matching the contract every example honors.

## Build

```bash
SITE_VERSION_KEY=next DIST_DIR=$PWD/dist npm install
SITE_VERSION_KEY=next DIST_DIR=$PWD/dist npm run build
# -> $PWD/dist/next/index.html
```

With `SITE_BASE` set:

```bash
SITE_VERSION_KEY=v1 SITE_BASE=docs DIST_DIR=$PWD/dist npm run build
# -> $PWD/dist/docs/v1/index.html
```

## Why VitePress alongside VuePress

VitePress is a Vite-based rewrite from the same team. It uses Vue 3, ships fast incremental builds, and has a different config surface (`base` + `outDir` directly on the root config object instead of nested under a theme). Keeping both examples lets readers compare the two Vue-flavored options side-by-side.
