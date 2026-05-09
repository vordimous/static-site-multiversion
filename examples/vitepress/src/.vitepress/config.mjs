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

// Inline injector: VitePress's default theme has Vue-managed routes, so we
// attach the version-switcher mount + shim include via the page's <head>
// after DOMContentLoaded. data-mode="hybrid" demos baked-then-replaced.
const switcherInject = `(function () {
  function inject() {
    if (document.getElementById('version-switcher')) return;
    var div = document.createElement('div');
    div.id = 'version-switcher';
    div.setAttribute('data-mode', 'hybrid');
    div.setAttribute('data-fallback', '../next/');
    var seed = document.createElement('script');
    seed.type = 'application/json';
    seed.id = 'version-switcher-seed';
    seed.textContent = '[{"key":"current","label":"current"}]';
    div.appendChild(seed);
    document.body.appendChild(div);
    var s = document.createElement('script');
    s.src = './switcher.js';
    s.defer = true;
    document.body.appendChild(s);
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();`

export default defineConfig({
  title: 'Versioned VitePress Example',
  description: `Docs at version ${versionKey}`,
  base: baseUrl,
  outDir,
  cleanUrls: true,
  head: [
    ['script', {}, switcherInject],
  ],
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
