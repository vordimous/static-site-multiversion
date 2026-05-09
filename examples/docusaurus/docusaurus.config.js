// Wires the static-site-multiversion builder contract into Docusaurus 2.
//
// Inputs (env, set by scripts/build-versions.sh):
//   SITE_VERSION_KEY  version slug being built
//   SITE_BASE         optional URL path prefix
//   DIST_DIR          shared output root (used by build.sh, not here)
//
// Docusaurus 2 uses MDX 1, top-level onBrokenMarkdownLinks (no markdown.hooks
// nesting), and ships with the React-classic preset on Webpack 5. The v3
// upgrade moved markdown options under `markdown.hooks` and switched MDX 3
// on by default.

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
  onBrokenMarkdownLinks: 'warn',
  i18n: { defaultLocale: 'en', locales: ['en'] },
  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: require.resolve('./sidebars.js'),
        },
        blog: false,
        theme: { customCss: require.resolve('./src/css/custom.css') },
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
