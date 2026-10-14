// Browser test for scripts/switcher.js. Serves synthetic pages from a fake
// origin through Playwright request routing, so no server is needed.

import { chromium } from 'playwright'
import { readFileSync } from 'node:fs'

const SWITCHER = readFileSync(new URL('../scripts/switcher.js', import.meta.url), 'utf8')
const ORIGIN = 'http://ssm.test'

let pass = 0
let fail = 0
function check(ok, msg) {
  if (ok) pass++
  else {
    fail++
    console.error(`  FAIL: ${msg}`)
  }
}

function html({ mode, canonical, seed, scriptSrc }) {
  const seedTag = seed
    ? `<script type="application/json" id="version-switcher-seed">${JSON.stringify(seed)}</script>`
    : ''
  return `<!doctype html><title>t</title>
<div id="version-switcher" data-mode="${mode}" data-canonical="${canonical}" data-fallback="/fallback/">${seedTag}</div>
<script src="${scriptSrc}" defer></script>`
}

async function withSite(browser, files, fn) {
  const context = await browser.newContext()
  await context.route(`${ORIGIN}/**`, route => {
    const { pathname } = new URL(route.request().url())
    if (pathname.endsWith('/switcher.js')) {
      return route.fulfill({ contentType: 'application/javascript', body: SWITCHER })
    }
    if (pathname in files) {
      const body = files[pathname]
      const json = pathname.endsWith('.json')
      return route.fulfill({ contentType: json ? 'application/json' : 'text/html', body: json ? JSON.stringify(body) : body })
    }
    return route.fulfill({ status: 404, body: 'not found' })
  })
  const page = await context.newPage()
  try {
    await fn(page)
  } finally {
    await context.close()
  }
}

const options = page =>
  page.$$eval('#version-switcher select option', opts => opts.map(o => ({ value: o.value, selected: o.selected })))

async function siteBaseEqualsKey(browser) {
  console.log('\nscenario: SITE_BASE segment equals a version key')
  const page = html({ mode: 'runtime', canonical: '/1.0/versions.json', scriptSrc: '../switcher.js' })
  await withSite(
    browser,
    {
      '/1.0/versions.json': [{ key: '1.0' }, { key: 'next' }],
      '/1.0/next/guide/': page,
      '/1.0/1.0/guide/': page,
    },
    async p => {
      await p.goto(`${ORIGIN}/1.0/next/guide/`)
      await p.waitForSelector('#version-switcher select')
      const opts = await options(p)
      check(opts.find(o => o.selected)?.value === 'next', `expected "next" selected, got ${JSON.stringify(opts)}`)
      await Promise.all([
        p.waitForURL(`${ORIGIN}/1.0/1.0/guide/`, { timeout: 5000 }).catch(() => {}),
        p.selectOption('#version-switcher select', '1.0'),
      ])
      check(new URL(p.url()).pathname === '/1.0/1.0/guide/', `expected navigation to /1.0/1.0/guide/, got ${p.url()}`)
    },
  )
}

async function hybridReplacesSeed(browser) {
  console.log('\nscenario: hybrid mode replaces the seed with the canonical list')
  await withSite(
    browser,
    {
      '/docs/versions.json': [{ key: '0.9' }, { key: 'next', label: 'Latest' }],
      '/docs/next/': html({
        mode: 'hybrid',
        canonical: '/docs/versions.json',
        seed: [{ key: 'current', label: 'current' }],
        scriptSrc: './switcher.js',
      }),
    },
    async p => {
      await p.goto(`${ORIGIN}/docs/next/`)
      await p.waitForFunction(() => document.querySelectorAll('#version-switcher select option').length === 2, null, { timeout: 5000 }).catch(() => {})
      const opts = await options(p)
      check(
        JSON.stringify(opts) === JSON.stringify([{ value: '0.9', selected: false }, { value: 'next', selected: true }]),
        `expected canonical options with "next" selected, got ${JSON.stringify(opts)}`,
      )
      check((await p.$$('#version-switcher select')).length === 1, 'expected exactly one select after the swap')
    },
  )
}

async function runtimeFallsBackToLink(browser) {
  console.log('\nscenario: runtime mode shows the fallback link when the canonical list is missing')
  await withSite(
    browser,
    { '/docs/next/': html({ mode: 'runtime', canonical: '/docs/versions.json', scriptSrc: './switcher.js' }) },
    async p => {
      await p.goto(`${ORIGIN}/docs/next/`)
      const link = await p.waitForSelector('#version-switcher a', { timeout: 5000 }).catch(() => null)
      check(link && (await link.getAttribute('href')) === '/fallback/', 'expected a "View all versions" link to data-fallback')
    },
  )
}

const browser = await chromium.launch()
try {
  await siteBaseEqualsKey(browser)
  await hybridReplacesSeed(browser)
  await runtimeFallsBackToLink(browser)
} finally {
  await browser.close()
}

console.log(`\nresults: ${pass} passed, ${fail} failed`)
process.exit(fail === 0 ? 0 : 1)
