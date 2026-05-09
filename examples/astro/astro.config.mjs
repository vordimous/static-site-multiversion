// Wires the static-site-multiversion builder contract into Astro 3.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//
// Astro 3 falls back to a local `./.astro/` staging dir when outDir is
// outside cwd (see `getOutDirWithinCwd` in astro/dist/core/build/common.js)
// and that staging path doesn't survive the build, so this config keeps
// outDir at the default `./dist` and lets build.sh move the output to the
// real $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/ after astro finishes.

import { defineConfig } from 'astro/config'

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''

const pathSegments = [siteBase, versionKey].filter(Boolean)
const base = `/${pathSegments.join('/')}/`

export default defineConfig({
  base,
  trailingSlash: 'always',
})
