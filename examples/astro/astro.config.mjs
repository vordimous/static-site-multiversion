// Wires the static-site-multiversion builder contract into Astro.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//   DIST_DIR          shared output root for all versions
//
// Astro writes flat to `outDir`, so the config combines the env vars into
// the per-version output path. `base` matches that path so internal links
// and asset URLs resolve when deployed.

import { defineConfig } from 'astro/config'
import { fileURLToPath } from 'node:url'
import path from 'node:path'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''
const distDir = process.env.DIST_DIR || path.resolve(__dirname, '../../dist')

const pathSegments = [siteBase, versionKey].filter(Boolean)
const base = `/${pathSegments.join('/')}/`
const outDir = path.join(distDir, ...pathSegments)

export default defineConfig({
  base,
  outDir,
  trailingSlash: 'always',
})
