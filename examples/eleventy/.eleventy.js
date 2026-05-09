// Wires the static-site-multiversion builder contract into Eleventy 2.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//   DIST_DIR          shared output root for all versions
//
// Eleventy 2 ships CommonJS-only config; this file is the v2-era spelling
// (.eleventy.js + module.exports). Eleventy 3's ESM config under
// eleventy.config.js is the eleventy-v3 tag.

const path = require('node:path')

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''
const distDir = process.env.DIST_DIR || path.resolve(__dirname, '../../dist')

const pathSegments = [siteBase, versionKey].filter(Boolean)
const pathPrefix = `/${pathSegments.join('/')}/`
const outputDir = path.join(distDir, ...pathSegments)

module.exports = function (eleventyConfig) {
  eleventyConfig.addGlobalData('siteVersionKey', versionKey)
  eleventyConfig.addGlobalData('pathPrefix', pathPrefix)

  return {
    pathPrefix,
    dir: {
      input: 'src',
      output: outputDir,
      includes: '_includes',
    },
    markdownTemplateEngine: 'njk',
    htmlTemplateEngine: 'njk',
  }
}
