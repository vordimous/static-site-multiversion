// Wires the static-site-multiversion builder contract into VitePress.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built (e.g. "next", "v1")
//   SITE_BASE         optional URL path prefix
//   DIST_DIR          shared output root
//
// Output: $DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/, with internal links
// and asset URLs that work when deployed under that path.

import { defineConfig } from 'vitepress'
import path from 'node:path'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''
const distRoot = process.env.DIST_DIR || path.resolve(__dirname, '../../../../dist')

const baseUrl = siteBase
  ? `/${siteBase}/${versionKey}/`
  : `/${versionKey}/`

const outDir = siteBase
  ? path.join(distRoot, siteBase, versionKey)
  : path.join(distRoot, versionKey)

const versionsPath = path.resolve(__dirname, '../versions.json')
let versionsJson = []
try {
  versionsJson = JSON.parse(readFileSync(versionsPath, 'utf8'))
} catch {
  // Optional file; an empty list is fine.
}

// The version switcher is rendered natively in the nav bar via a custom
// theme component (.vitepress/theme/VersionDropdown.vue). The component
// fetches /<base>/versions.json at runtime to discover newer versions
// added after this build was cached, so no separate shim or bolted-on
// mount is needed here.

export default defineConfig({
  title: 'Versioned VitePress Example',
  description: `Docs at version ${versionKey}`,
  base: baseUrl,
  outDir,
  cleanUrls: true,
  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/' },
    ],
    sidebar: [
      { text: 'Guide', items: [{ text: 'Getting started', link: '/guide/' }] },
    ],
    socialLinks: [
      { icon: 'github', link: 'https://github.com/vordimous/static-site-multiversion' },
    ],
  },
  transformPageData(pageData) {
    pageData.frontmatter ??= {}
    pageData.frontmatter.versionKey = versionKey
    pageData.frontmatter.versions = versionsJson
  },
})
