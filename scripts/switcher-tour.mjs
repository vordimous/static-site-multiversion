#!/usr/bin/env node
//
// Drives Playwright through each /<builder>/next/ on the running demo,
// finds the version switcher (either a bolted-on <select> or the new
// native nav dropdown per builder), opens it, and saves a per-builder
// PNG plus a summary of the menu items.
//
// Usage:
//   node scripts/switcher-tour.mjs                # headless
//   HEADED=1 node scripts/switcher-tour.mjs       # watch live in Chromium
//   HEADED=1 HOLD=4 node scripts/switcher-tour.mjs   # 4s pause per builder

import { chromium } from 'playwright'
import fs from 'node:fs/promises'
import path from 'node:path'

const BASE = process.env.BASE || 'http://localhost:8080'
const HEADED = process.env.HEADED === '1'
const HOLD_MS = (parseInt(process.env.HOLD || '0', 10) || 0) * 1000
const OUT_DIR = path.resolve('tmp/tour')

// Each entry can specify either:
//   bolted: true                — use the legacy <div id="version-switcher"> dropdown
//   native: {trigger, item}     — selectors for a real nav dropdown
const BUILDERS = [
  { name: 'plain-html', mode: 'hybrid', bolted: true },
  { name: 'eleventy',   mode: 'hybrid', bolted: true },
  { name: 'hugo',       mode: 'runtime', bolted: true },
  { name: 'astro',      mode: 'runtime', bolted: true },
  { name: 'mkdocs',     mode: 'baked',   native: { trigger: 'a.dropdown-toggle', item: '.dropdown-menu a.dropdown-item' } },
  { name: 'vitepress',  mode: 'hybrid',  native: { trigger: '.vp-version-menu .trigger', item: '.vp-version-menu .item' } },
  { name: 'vuepress',   mode: 'baked',   native: { trigger: 'button.vp-navbar-dropdown-title', item: 'ul.vp-navbar-dropdown a' } },
  { name: 'docusaurus', mode: 'baked',   native: { trigger: '.navbar__items--right .dropdown > .navbar__link', item: '.dropdown__menu .dropdown__link' } },
]

await fs.mkdir(OUT_DIR, { recursive: true })

const browser = await chromium.launch({ headless: !HEADED })
const ctx = await browser.newContext({ viewport: { width: 1280, height: 720 } })
const page = await ctx.newPage()

const summary = []

for (const b of BUILDERS) {
  const url = `${BASE}/${b.name}/next/`
  process.stdout.write(`tour: ${b.name.padEnd(11)} (${b.mode}) -> ${url}\n`)

  const resp = await page.goto(url, { waitUntil: 'networkidle' })
  if (!resp || !resp.ok()) {
    summary.push({ builder: b.name, mode: b.mode, kind: '-', error: `${resp?.status() ?? 'no-response'}` })
    continue
  }
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1500) // let hybrid/runtime fetch resolve

  let opts = null
  let kind = ''

  if (b.bolted) {
    kind = 'bolted'
    opts = await page.evaluate(() => {
      const mount = document.getElementById('version-switcher')
      if (!mount) return null
      const select = mount.querySelector('select')
      if (!select) return null
      // Inline-expand for the screenshot.
      select.size = Math.max(select.options.length, 2)
      mount.style.padding = '0.75rem'
      mount.style.background = '#fffbe8'
      mount.style.border = '2px solid #cfa800'
      mount.style.borderRadius = '6px'
      mount.style.margin = '1rem 0'
      select.scrollIntoView({ block: 'center' })
      return Array.from(select.options).map(o => ({
        value: o.value,
        label: o.textContent,
        selected: o.selected,
      }))
    })
  } else if (b.native) {
    kind = 'native'
    // Open the dropdown so the screenshot shows the menu.
    const trigger = await page.$(b.native.trigger)
    if (trigger) {
      await trigger.click({ force: true }).catch(() => {})
      await page.waitForTimeout(400)
      const here = page.url()
      opts = await page.$$eval(b.native.item, (els, currentUrl) => {
        const seen = new Set()
        const here = new URL(currentUrl)
        const out = []
        for (const e of els) {
          const href = e.getAttribute('href') || ''
          if (!href || seen.has(href)) continue
          seen.add(href)
          let selected = false
          try {
            const u = new URL(e.href, currentUrl)
            selected = u.pathname.replace(/\/$/, '') === here.pathname.replace(/\/$/, '')
          } catch {}
          out.push({ value: href, label: e.textContent.trim(), selected })
        }
        return out
      }, here)
    }
  }

  const out = path.join(OUT_DIR, `${b.name}.png`)
  await page.screenshot({ path: out })
  if (HEADED && HOLD_MS > 0) await page.waitForTimeout(HOLD_MS)

  if (!opts) {
    summary.push({ builder: b.name, mode: b.mode, kind, error: 'no menu found' })
  } else {
    summary.push({ builder: b.name, mode: b.mode, kind, options: opts })
  }
}

await fs.writeFile(
  path.join(OUT_DIR, 'summary.json'),
  JSON.stringify(summary, null, 2) + '\n',
)

process.stdout.write('\nsummary:\n')
for (const row of summary) {
  if (row.error) {
    process.stdout.write(`  ${row.builder.padEnd(11)} (${row.mode.padEnd(7)} ${row.kind.padEnd(6)}) ERROR: ${row.error}\n`)
    continue
  }
  const list = row.options
    .map(o => (o.selected ? `*${o.label.trim()}*` : o.label.trim()))
    .join(', ')
  process.stdout.write(`  ${row.builder.padEnd(11)} (${row.mode.padEnd(7)} ${row.kind.padEnd(6)}) [${list}]\n`)
}

await browser.close()
