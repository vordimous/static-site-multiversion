#!/usr/bin/env bash
#
# Drives Playwright's bundled chromium against a URL or path and writes the
# screenshot somewhere we can read it back.
#
# Usage:
#   scripts/screenshot.sh /vitepress/0.9/                      # path on localhost:8080
#   scripts/screenshot.sh http://localhost:8080/eleventy/v3/   # full URL
#   scripts/screenshot.sh /astro/next/ tmp/astro-next.png      # custom output path
#
# Optional env:
#   BASE       base URL when the first arg is a path (default: http://localhost:8080)
#   FULL_PAGE  set to 1 to capture the full scroll height
#   NO_JS      set to 1 to render with JavaScript disabled
#   HEADED     set to 1 to launch a visible Chromium window (so you can watch
#              the run live). The window stays open for a few seconds after
#              the screenshot so you have time to see it.
#   HOLD       seconds to leave the headed window open after capture (default: 3)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

[ "$#" -ge 1 ] || { echo "usage: $0 <path-or-url> [output.png]" >&2; exit 2; }

target="$1"
out="${2:-tmp/shot-$(date +%s).png}"
base="${BASE:-http://localhost:8080}"

case "$target" in
  http://*|https://*) url="$target" ;;
  *)                  url="${base%/}/${target#/}" ;;
esac

mkdir -p "$(dirname "$out")"

# Inline JS reads vars from process.env; literal expressions inside the
# single-quoted block intentionally do not expand at the shell layer.
# shellcheck disable=SC2016
FULL_PAGE="${FULL_PAGE:-0}" NO_JS="${NO_JS:-0}" HEADED="${HEADED:-0}" HOLD="${HOLD:-3}" \
URL="$url" OUT="$out" \
  node --input-type=module -e '
    import { chromium } from "playwright";
    const { URL: u, OUT: out, FULL_PAGE, NO_JS, HEADED, HOLD } = process.env;
    const headed = HEADED === "1";
    const browser = await chromium.launch({ headless: !headed });
    const ctx = await browser.newContext({ javaScriptEnabled: NO_JS !== "1" });
    const page = await ctx.newPage();
    const resp = await page.goto(u, { waitUntil: "networkidle" });
    if (!resp || !resp.ok()) {
      console.error(`screenshot: ${u} returned ${resp ? resp.status() : "no response"}`);
      process.exit(1);
    }
    // Defer-loaded scripts can fire fetches after the initial networkidle;
    // give the page a brief moment to settle so the screenshot captures the
    // post-fetch state (e.g. switcher.js replacing its seed dropdown).
    await page.waitForLoadState("networkidle");
    await page.waitForTimeout(parseInt(process.env.SETTLE || "800", 10));
    await page.screenshot({ path: out, fullPage: FULL_PAGE === "1" });
    console.log(`screenshot: wrote ${out} (${u})`);
    if (headed) {
      const ms = Math.max(0, parseInt(HOLD, 10) * 1000) || 3000;
      console.log(`screenshot: holding window for ${ms}ms (HOLD=${HOLD}s)`);
      await page.waitForTimeout(ms);
    }
    await browser.close();
  '
