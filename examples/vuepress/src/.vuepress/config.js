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
import path from 'node:path'

const __dirname = path.dirname(fileURLToPath(import.meta.url))

const versionKey = process.env.SITE_VERSION_KEY || 'next'
const siteBase = process.env.SITE_BASE || ''
const distDir = process.env.DIST_DIR || path.resolve(__dirname, '../../../../dist')

const pathSegments = [siteBase, versionKey].filter(Boolean)
const base = `/${pathSegments.join('/')}/`
const dest = path.join(distDir, ...pathSegments)

export default defineUserConfig({
  base,
  dest,
  bundler: viteBundler(),
  lang: 'en-US',
  title: 'Versioned VuePress Example',
  description: `Docs at version ${versionKey}`,
  theme: defaultTheme({
    repo: 'vordimous/static-site-multiversion',
    navbar: [
      { text: 'Home', link: '/' },
      { text: 'Guide', link: '/guide/' },
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
