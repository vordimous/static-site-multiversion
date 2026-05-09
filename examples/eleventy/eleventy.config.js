// Wires the static-site-multiversion builder contract into Eleventy 3.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//   DIST_DIR          shared output root for all versions
//
// Eleventy supports both `pathPrefix` (URL prefix used when generating links
// via the `url` filter) and `dir.output` natively, so no shell wrapper is
// needed; the config reads env directly and returns the right values.

import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''
const distDir = process.env.DIST_DIR || path.resolve(__dirname, '../../dist')

const pathSegments = [siteBase, versionKey].filter(Boolean)
const pathPrefix = `/${pathSegments.join('/')}/`
const outputDir = path.join(distDir, ...pathSegments)

export default function (eleventyConfig) {
  eleventyConfig.addGlobalData('siteVersionKey', versionKey)
  eleventyConfig.addGlobalData('pathPrefix', pathPrefix)
}

export const config = {
  pathPrefix,
  dir: {
    input: 'src',
    output: outputDir,
    includes: '_includes',
  },
  markdownTemplateEngine: 'njk',
  htmlTemplateEngine: 'njk',
}
