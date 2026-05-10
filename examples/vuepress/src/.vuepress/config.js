// Wires the static-site-multiversion builder contract into VuePress.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built (e.g. "next", "0.9")
//   SITE_BASE         optional URL path prefix (e.g. "my-docs")
//   DIST_DIR          shared output root for all versions
//
// VuePress writes flat to `dest` (it does not auto-nest under `base`), so
// dest gets the full per-version path while base supplies the matching URL
// prefix so links resolve correctly when deployed.

import { defineUserConfig } from 'vuepress'
import { defaultTheme } from '@vuepress/theme-default'
import { viteBundler } from '@vuepress/bundler-vite'
import { fileURLToPath } from 'node:url'
import { readFileSync } from 'node:fs'
import path from 'node:path'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''
const distDir = process.env.DIST_DIR || path.resolve(__dirname, '../../../../dist')

const pathSegments = [siteBase, versionKey].filter(Boolean)
const base = `/${pathSegments.join('/')}/`
const dest = path.join(distDir, ...pathSegments)

// VuePress is the "baked" mode example: the navbar's version dropdown
// is generated statically at build time and never updated at runtime.
// A frozen v0.9 build will always show the versions known when v0.9
// was cut. Mirrors the zilla-docs original.
//
// Sources for the baked list:
//   - $DEPLOY_VERSIONS (orchestrator-exported merged manifest path) —
//     the full historical list. For our demo: deploy-versions.demo.json
//     plus this builder's per-example deploy-versions.json.
//   - The `next` entry, always added so users can navigate back to HEAD.
const seedPath = path.resolve(__dirname, '../versions.json')
let seed = []
try {
  seed = JSON.parse(readFileSync(seedPath, 'utf8'))
} catch {
  // Optional; just an empty seed.
}

let deployList = []
if (process.env.DEPLOY_VERSIONS) {
  try {
    deployList = JSON.parse(readFileSync(process.env.DEPLOY_VERSIONS, 'utf8'))
  } catch {
    // Missing or unreadable; just an empty deploy list.
  }
}

const builderBase = siteBase ? `/${siteBase}/` : '/'
const seenKeys = new Set()
const versionItems = []
const correctHrefs = []   // for the runtime href patcher (see below)

const pushItem = (key, label) => {
  if (!key || key === 'current' || seenKeys.has(key)) return
  seenKeys.add(key)
  const text = label || key
  const link = `${builderBase}${key}/`
  versionItems.push({ text, link })
  correctHrefs.push({ text, href: link })
}

// Order: deploy-versions first, then next, then anything seed-only.
deployList.forEach(v => pushItem(v.key, v.label))
pushItem(versionKey, versionKey)
seed.forEach(v => pushItem(v.key, v.label))

// VuePress's default theme renders navbar dropdown children through
// vue-router with absolute paths treated as route paths relative to the
// build's `base`. Under a path-prefixed deploy (e.g. project Pages at
// /<repo>/) that doubles the prefix in rendered hrefs:
//   link "/static-site-multiversion/vuepress/0.9/"
//        -> rendered href "/static-site-multiversion/vuepress/next/static-site-multiversion/vuepress/0.9/"
// Runtime patcher fixes the hrefs after Vue hydrates by indexing into the
// dropdown's <a> elements with the correctly-formed paths we computed at
// build time.
const switcherHrefFix = `(function () {
  var ITEMS = ${JSON.stringify(correctHrefs)};
  function fix() {
    // VuePress's default theme renders the dropdown twice — once for the
    // desktop nav, once for the mobile nav screen. Both share the same
    // selector and same item order, so patch every anchor by index modulo
    // ITEMS.length.
    var anchors = document.querySelectorAll('ul.vp-navbar-dropdown a');
    if (!anchors.length || ITEMS.length === 0) return;
    anchors.forEach(function (a, i) {
      var item = ITEMS[i % ITEMS.length];
      if (item) a.setAttribute('href', item.href);
    });
  }
  // Periodic in case Vue re-renders (e.g. on color-mode toggle).
  setInterval(fix, 500);
})();`

// Patching the DOM href is enough for `<a>.href` reads but vue-router
// intercepts the click and dispatches via its internal route table,
// which still has the doubled-prefix path from config. Capture-phase
// click handler overrides that: it preventDefaults the framework's
// click and does a plain window.location assignment to the correct
// absolute URL.
const switcherClickFix = `(function () {
  var ITEMS = ${JSON.stringify(correctHrefs)};
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest && e.target.closest('ul.vp-navbar-dropdown a');
    if (!a) return;
    var anchors = document.querySelectorAll('ul.vp-navbar-dropdown a');
    var idx = Array.prototype.indexOf.call(anchors, a);
    if (idx < 0) return;
    var item = ITEMS[idx % ITEMS.length];
    if (!item) return;
    e.preventDefault();
    e.stopPropagation();
    window.location.href = item.href;
  }, true);
})();`

export default defineUserConfig({
  base,
  dest,
  bundler: viteBundler(),
  lang: 'en-US',
  title: 'Versioned VuePress Example',
  description: `Docs at version ${versionKey}`,
  head: [
    ['script', {}, switcherHrefFix],
    ['script', {}, switcherClickFix],
  ],
  theme: defaultTheme({
    repo: 'vordimous/static-site-multiversion',
    navbar: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/' },
      { text: versionKey, children: versionItems },
    ],
    sidebar: {
      '/guide/': [
        {
          text: 'Guide',
          children: ['/guide/getting-started.md'],
        },
      ],
    },
  }),
})
