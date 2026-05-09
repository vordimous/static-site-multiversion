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
const pushItem = (key, label) => {
  if (!key || key === 'current' || seenKeys.has(key)) return
  seenKeys.add(key)
  dropdownItems.push({ label: label || key, href: `${builderBase}${key}/` })
}
deployList.forEach(v => pushItem(v.key, v.label))
pushItem(versionKey, versionKey)

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
