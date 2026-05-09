// Wires the static-site-multiversion builder contract into Astro.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//
// Astro 3 and 4 both fall back to a local `./.astro/` staging dir when
// outDir is outside cwd (see `getOutDirWithinCwd` in astro/dist/core/
// build/common.js) and the fallback path doesn't survive the build, so
// this config keeps outDir at the default `./dist` and lets build.sh
// copy the output to the env-derived path afterward.

import { defineConfig } from 'astro/config'

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''

const pathSegments = [siteBase, versionKey].filter(Boolean)
const base = `/${pathSegments.join('/')}/`

export default defineConfig({
  base,
  trailingSlash: 'always',
})
