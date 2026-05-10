// Wires the static-site-multiversion builder contract into Docusaurus 3.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//   DIST_DIR          shared output root (used by build.sh, not here)
//   DEPLOY_VERSIONS   path to the merged manifest (for baked-mode dropdown)
//
// Docusaurus reads `baseUrl` from the config; the output directory is set via
// the CLI flag `--out-dir` in build.sh, since it can't be derived from env at
// config-evaluation time without a wrapper.

const fs = require('node:fs')

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''

const pathSegments = [siteBase, versionKey].filter(Boolean)
const baseUrl = `/${pathSegments.join('/')}/`

// Docusaurus is the "baked" mode example for the React-themed family.
// The orchestrator exports DEPLOY_VERSIONS pointing at the merged
// manifest path; we read it synchronously and bake the navbar's
// version dropdown items at build time. No runtime fetch.
const builderBase = siteBase ? `/${siteBase}/` : '/'
let deployList = []
if (process.env.DEPLOY_VERSIONS) {
  try {
    deployList = JSON.parse(fs.readFileSync(process.env.DEPLOY_VERSIONS, 'utf8'))
  } catch {
    // Missing or unreadable; the dropdown gets only the build-time `next` entry.
  }
}

const seenKeys = new Set()
const dropdownItems = []
const correctHrefs = []   // for the runtime href patcher (see below)
const pushItem = (key, label) => {
  if (!key || key === 'current' || seenKeys.has(key)) return
  seenKeys.add(key)
  const text = label || key
  const href = `${builderBase}${key}/`
  dropdownItems.push({ label: text, href })
  correctHrefs.push({ label: text, href })
}
deployList.forEach(v => pushItem(v.key, v.label))
pushItem(versionKey, versionKey)

// Docusaurus, like VuePress, treats internal navbar links as router-
// relative and prepends the build's baseUrl. Under /<repo>/ deploys
// that doubles the prefix in rendered hrefs. Runtime patcher fixes the
// hrefs after React hydrates by indexing into the dropdown's <a> tags
// with the correctly-formed paths we computed at build time.
const switcherHrefFix = `(function () {
  var ITEMS = ${JSON.stringify(correctHrefs)};
  function fix() {
    var anchors = document.querySelectorAll('.dropdown__menu .dropdown__link');
    if (anchors.length !== ITEMS.length) return;
    ITEMS.forEach(function (item, i) {
      anchors[i].setAttribute('href', item.href);
    });
  }
  setInterval(fix, 500);
})();`

// React Router intercepts internal `<a>` clicks and dispatches via its
// internal route table, which still holds the doubled-prefix path. The
// DOM patcher above corrects href attributes for non-click consumers
// (and styling), but clicks need a capture-phase override.
const switcherClickFix = `(function () {
  var ITEMS = ${JSON.stringify(correctHrefs)};
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest && e.target.closest('.dropdown__menu .dropdown__link');
    if (!a) return;
    var anchors = document.querySelectorAll('.dropdown__menu .dropdown__link');
    var idx = Array.prototype.indexOf.call(anchors, a);
    if (idx < 0) return;
    var item = ITEMS[idx];
    if (!item) return;
    e.preventDefault();
    e.stopPropagation();
    window.location.href = item.href;
  }, true);
})();`

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'Versioned Docusaurus Example',
  tagline: `Docs at version ${versionKey}`,
  favicon: 'img/favicon.ico',
  url: 'https://example.com',
  baseUrl,
  organizationName: 'vordimous',
  projectName: 'static-site-multiversion',
  onBrokenLinks: 'warn',
  markdown: {
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },
  headTags: [
    {
      tagName: 'script',
      attributes: {},
      innerHTML: switcherHrefFix,
    },
    {
      tagName: 'script',
      attributes: {},
      innerHTML: switcherClickFix,
    },
  ],
  i18n: { defaultLocale: 'en', locales: ['en'] },
  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.js',
        },
        blog: false,
        theme: { customCss: './src/css/custom.css' },
      },
    ],
  ],
  themeConfig: {
    navbar: {
      title: 'Versioned Docusaurus',
      items: [
        { to: '/', label: 'Docs', position: 'left' },
        {
          type: 'dropdown',
          label: versionKey,
          position: 'right',
          items: dropdownItems,
        },
      ],
    },
  },
}

module.exports = config
