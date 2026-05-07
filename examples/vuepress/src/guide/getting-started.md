# Getting started

This page exists so the build produces more than one HTML file. Edit it freely when adapting the example to a real site.

## Build locally

```bash
pnpm install
pnpm build
```

Output lands in `../../dist/next/` by default. Override `SITE_VERSION_KEY`, `SITE_BASE`, and `DIST_DIR` to change the layout.

## Multi-version build

From the host repo root, run `scripts/build-versions.sh` with `BUILD_CMD="pnpm --filter ./examples/vuepress build"` (or whatever invocation reaches this example).
