// Wires the static-site-multiversion builder contract into Docusaurus 3.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//   DIST_DIR          shared output root (used by build.sh, not here)
//
// Docusaurus reads `baseUrl` from the config; the output directory is set via
// the CLI flag `--out-dir` in build.sh, since it can't be derived from env at
// config-evaluation time without a wrapper.

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''

const pathSegments = [siteBase, versionKey].filter(Boolean)
const baseUrl = `/${pathSegments.join('/')}/`

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
      items: [{ to: '/', label: 'Docs', position: 'left' }],
    },
  },
}

module.exports = config
