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

const pushItem = (key, label) => {
  if (!key || key === 'current' || seenKeys.has(key)) return
  seenKeys.add(key)
  versionItems.push({ text: label || key, link: `${builderBase}${key}/` })
}

// Order: deploy-versions first, then next, then anything seed-only.
deployList.forEach(v => pushItem(v.key, v.label))
pushItem(versionKey, versionKey)
seed.forEach(v => pushItem(v.key, v.label))

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
