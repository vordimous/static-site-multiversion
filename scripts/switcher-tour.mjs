#!/usr/bin/env node
//
// Drives Playwright through every /<builder>/<key>/ on the running demo.
//
// For each builder it:
//   1. Visits /<builder>/next/, finds the version switcher (bolted-on
//      <select> or native nav dropdown), and reads the option list.
//   2. For each option, navigates to that version's URL, asserts the
//      response is 2xx, captures any failed network requests (broken
//      assets), and verifies the dropdown is still present.
//   3. Saves a per-builder screenshot of the /next/ page with the menu
//      expanded, plus tmp/tour/summary.json with full results.
//
// Usage:
//   node scripts/switcher-tour.mjs                   # headless
//   HEADED=1 node scripts/switcher-tour.mjs          # watch live
//   HEADED=1 HOLD=4 node scripts/switcher-tour.mjs   # 4s pause per builder
//   BASE=https://vordimous.github.io/static-site-multiversion node scripts/switcher-tour.mjs

import { chromium } from 'playwright'
import fs from 'node:fs/promises'
import path from 'node:path'

const BASE = process.env.BASE || 'http://localhost:8080'
const HEADED = process.env.HEADED === '1'
const HOLD_MS = (parseInt(process.env.HOLD || '0', 10) || 0) * 1000
const OUT_DIR = path.resolve('tmp/tour')

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

// Track failed network requests as we go; flushed per visit.
let failedRequests = []
page.on('requestfailed', req => failedRequests.push({ url: req.url(), error: req.failure()?.errorText }))
page.on('response', resp => {
  if (resp.status() >= 400) failedRequests.push({ url: resp.url(), status: resp.status() })
})

async function readMenu(b) {
  if (b.bolted) {
    return await page.evaluate(() => {
      const mount = document.getElementById('version-switcher')
      if (!mount) return null
      const select = mount.querySelector('select')
      if (!select) return null
      return Array.from(select.options).map(o => ({
        value: o.value,
        label: o.textContent.trim(),
        selected: o.selected,
        // For bolted-on selects we synthesize the navigation URL from the
        // current pathname swapping the version segment.
        href: null,
      }))
    })
  }
  if (b.native) {
    const trigger = await page.$(b.native.trigger)
    if (!trigger) return null
    await trigger.click({ force: true }).catch(() => {})
    await page.waitForTimeout(300)
    const here = page.url()
    return await page.$$eval(b.native.item, (els, currentUrl) => {
      const seen = new Set()
      const out = []
      for (const e of els) {
        const href = e.getAttribute('href') || ''
        if (!href || seen.has(href)) continue
        seen.add(href)
        let selected = false
        try {
          const u = new URL(e.href, currentUrl)
          selected = u.pathname.replace(/\/$/, '') === new URL(currentUrl).pathname.replace(/\/$/, '')
        } catch {}
        out.push({
          value: href,
          label: e.textContent.trim(),
          selected,
          href: new URL(e.href || href, currentUrl).toString(),
        })
      }
      return out
    }, here)
  }
  return null
}

// For bolted-on selects, derive each version's URL by swapping the
// matching segment in the current pathname (the same logic the shim
// uses to navigate when the user picks an option).
function bolted_urls(currentUrl, options) {
  const u = new URL(currentUrl)
  const segments = u.pathname.split('/').filter(Boolean)
  const keys = options.map(o => o.value)
  const idx = segments.findIndex(s => keys.includes(s))
  return options.map(o => {
    const segs = segments.slice()
    if (idx >= 0) segs[idx] = o.value
    const path = '/' + segs.join('/') + (u.pathname.endsWith('/') ? '/' : '')
    return { ...o, href: new URL(path, u).toString() }
  })
}

const summary = []

for (const b of BUILDERS) {
  const url = `${BASE}/${b.name}/next/`
  process.stdout.write(`tour: ${b.name}\n`)

  failedRequests = []
  const resp = await page.goto(url, { waitUntil: 'networkidle' })
  if (!resp || !resp.ok()) {
    summary.push({ builder: b.name, mode: b.mode, kind: '-', error: `next returned ${resp?.status() ?? 'no-response'}` })
    continue
  }
  await page.waitForLoadState('networkidle')
  await page.waitForTimeout(1500)

  let menu = await readMenu(b)
  if (!menu || !menu.length) {
    summary.push({ builder: b.name, mode: b.mode, kind: b.bolted ? 'bolted' : 'native', error: 'no menu found' })
    continue
  }
  if (b.bolted) menu = bolted_urls(page.url(), menu)

  // Snapshot of /next/ with the menu open for the screenshot output.
  if (b.bolted) {
    await page.evaluate(() => {
      const mount = document.getElementById('version-switcher')
      const select = mount?.querySelector('select')
      if (!select) return
      select.size = Math.max(select.options.length, 2)
      mount.style.padding = '0.75rem'
      mount.style.background = '#fffbe8'
      mount.style.border = '2px solid #cfa800'
      mount.style.borderRadius = '6px'
      mount.style.margin = '1rem 0'
      select.scrollIntoView({ block: 'center' })
    })
  }
  await page.screenshot({ path: path.join(OUT_DIR, `${b.name}.png`) })
  if (HEADED && HOLD_MS > 0) await page.waitForTimeout(HOLD_MS)

  // Visit every version. Track per-version status + asset health.
  const visits = []
  for (const opt of menu) {
    if (!opt.href) continue
    failedRequests = []
    let status = null
    try {
      const r = await page.goto(opt.href, { waitUntil: 'networkidle', timeout: 30000 })
      status = r ? r.status() : null
    } catch (e) {
      status = `error: ${e.message}`
    }
    await page.waitForTimeout(800)
    const dropdownPresent = b.bolted
      ? await page.evaluate(() => !!document.querySelector('#version-switcher select'))
      : await page.evaluate(t => !!document.querySelector(t), b.native.trigger)

    visits.push({
      key: opt.value,
      url: opt.href,
      status,
      dropdownPresent,
      // Historical versions predate the switcher integration; we only
      // require a dropdown on the build-time `next` version.
      isCurrent: opt.value === 'next' || opt.href?.endsWith('/next/'),
      brokenRequests: failedRequests
        .filter(r => !r.url.includes('/favicon.ico'))
        .map(r => `${r.status || r.error} ${r.url}`),
    })
  }

  summary.push({
    builder: b.name,
    mode: b.mode,
    kind: b.bolted ? 'bolted' : 'native',
    options: menu.map(o => ({ value: o.value, label: o.label, selected: o.selected })),
    visits,
  })
}

await fs.writeFile(
  path.join(OUT_DIR, 'summary.json'),
  JSON.stringify(summary, null, 2) + '\n',
)

// Pretty-print
process.stdout.write('\nresults:\n')
let totalOk = 0, totalFail = 0
for (const row of summary) {
  if (row.error) {
    process.stdout.write(`  ${row.builder.padEnd(11)} ${row.kind.padEnd(6)} ERROR: ${row.error}\n`)
    totalFail++
    continue
  }
  process.stdout.write(`  ${row.builder.padEnd(11)} ${row.kind.padEnd(6)} ${row.options.length} versions\n`)
  for (const v of row.visits) {
    // Historical versions predate the switcher integration, so no menu
    // is acceptable there. Current (next) must have a menu.
    const menuOk = v.isCurrent ? v.dropdownPresent : true
    const ok = v.status === 200 && menuOk && v.brokenRequests.length === 0
    if (ok) totalOk++; else totalFail++
    const flag = ok ? 'OK ' : 'XX '
    const drop = v.dropdownPresent ? 'menu  ' : (v.isCurrent ? 'NO-menu' : 'no-menu')
    const broken = v.brokenRequests.length ? ` broken=${v.brokenRequests.length}` : ''
    process.stdout.write(`    ${flag} ${String(v.status).padEnd(4)} ${drop} ${v.key}${broken}\n`)
    for (const br of v.brokenRequests.slice(0, 3)) {
      process.stdout.write(`        ! ${br}\n`)
    }
  }
}
process.stdout.write(`\n${totalOk} ok, ${totalFail} fail\n`)

await browser.close()
process.exit(totalFail === 0 ? 0 : 1)
