#!/usr/bin/env node
//
// Drives Playwright through every /<builder>/<key>/ on the running demo.
//
// For each builder it:
//   1. Visits /<builder>/next/, finds the version switcher (bolted-on
//      <select> or native nav dropdown), and reads the option list.
//   2. For each option, CLICKS the matching dropdown item, waits for
//      navigation, asserts the resulting URL matches the expected
//      version path, captures any failed network requests, and verifies
//      the dropdown is still present on the destination page.
//   3. Requires the dropdown to be present on every version (next AND
//      historical). The dropdown is part of the contract — historical
//      builds that lack it are real bugs to fix, not exemptions.
//   4. Saves a per-builder screenshot of the /next/ page with the menu
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

// Trims trailing slashes / index.html so URL comparisons are robust
// across builders that emit foo/ vs foo/index.html.
function normalizePath(p) {
  return (p || '').replace(/\/index\.html$/, '/').replace(/\/+$/, '') || '/'
}

// Clicks the dropdown item that corresponds to `opt`, dispatching a
// real change/click event so the page navigates exactly the way a
// human-driven click would. Bolted-on <select>s navigate via their
// change handler; native nav dropdowns navigate via the anchor's
// default click action.
async function clickItem(b, opt) {
  if (b.bolted) {
    // selectOption fires the 'change' event the shim listens for.
    await page.selectOption('#version-switcher select', opt.value)
    return
  }
  // Native dropdown: open the trigger, then click the anchor whose
  // raw href attribute matches what we captured. We iterate locators
  // instead of using a CSS attribute selector to avoid escaping
  // edge cases in the captured href values.
  const trigger = await page.$(b.native.trigger)
  if (trigger) await trigger.click({ force: true }).catch(() => {})
  await page.waitForTimeout(200)
  const items = page.locator(b.native.item)
  const count = await items.count()
  for (let i = 0; i < count; i++) {
    const item = items.nth(i)
    const href = await item.getAttribute('href')
    if (href === opt.value) {
      await item.click()
      return
    }
  }
  throw new Error(`menu item not found for href=${opt.value}`)
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

  // Click every version's dropdown item in turn. Chains across pages
  // (no goto reset) so we exercise the click path from each visited
  // version, not just from /next/.
  const visits = []
  for (const opt of menu) {
    if (!opt.href) continue
    failedRequests = []
    const expectedPath = normalizePath(new URL(opt.href).pathname)
    let status = null
    let clickError = null

    // Capture the document-level response for the destination so we can
    // report the HTTP status. Pages 404s and redirects show up here.
    let navStatus = null
    const onResponse = (resp) => {
      try {
        if (resp.request().resourceType() !== 'document') return
        if (normalizePath(new URL(resp.url()).pathname) !== expectedPath) return
        navStatus = resp.status()
      } catch { /* swallow */ }
    }
    page.on('response', onResponse)

    try {
      // Run the click and the URL wait in parallel: clickItem triggers
      // navigation; waitForURL resolves once the page actually lands at
      // the expected path. waitForURL is robust to trailing-slash /
      // index.html differences via the predicate.
      await Promise.all([
        page.waitForURL(
          (u) => normalizePath(new URL(u).pathname) === expectedPath,
          { timeout: 30000 },
        ),
        clickItem(b, opt),
      ])
      await page.waitForLoadState('networkidle')
      status = navStatus ?? 'unknown'
    } catch (e) {
      clickError = e.message
      status = `error: ${e.message}`
    } finally {
      page.off('response', onResponse)
    }
    await page.waitForTimeout(400)

    const actualPath = normalizePath(new URL(page.url()).pathname)
    const urlMatch = actualPath === expectedPath

    const dropdownPresent = b.bolted
      ? await page.evaluate(() => !!document.querySelector('#version-switcher select'))
      : await page.evaluate(t => !!document.querySelector(t), b.native.trigger)

    visits.push({
      key: opt.value,
      url: opt.href,
      expectedPath,
      actualPath,
      urlMatch,
      status,
      clickError,
      dropdownPresent,
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
    // Dropdown is part of the contract on every version page, not just
    // /next/ — historical builds that lack it are real bugs.
    const ok = v.status === 200
      && v.urlMatch
      && v.dropdownPresent
      && v.brokenRequests.length === 0
      && !v.clickError
    if (ok) totalOk++; else totalFail++
    const flag = ok ? 'OK ' : 'XX '
    const drop = v.dropdownPresent ? 'menu  ' : 'NO-menu'
    const broken = v.brokenRequests.length ? ` broken=${v.brokenRequests.length}` : ''
    const urlNote = v.urlMatch ? '' : ` URL-mismatch(got=${v.actualPath})`
    process.stdout.write(`    ${flag} ${String(v.status).padEnd(4)} ${drop} ${v.key}${urlNote}${broken}\n`)
    if (v.clickError) {
      process.stdout.write(`        ! click: ${v.clickError}\n`)
    }
    for (const br of v.brokenRequests.slice(0, 3)) {
      process.stdout.write(`        ! ${br}\n`)
    }
  }
}
process.stdout.write(`\n${totalOk} ok, ${totalFail} fail\n`)

await browser.close()
process.exit(totalFail === 0 ? 0 : 1)
