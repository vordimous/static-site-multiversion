#!/usr/bin/env bash
#
# Browser test for scripts/switcher.js. Needs the root devDependencies and a
# Playwright Chromium:
#   npm ci && npx playwright install chromium

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -d "$REPO_ROOT/node_modules/playwright" ]; then
  echo "FAIL: playwright not installed. Run: npm ci && npx playwright install chromium" >&2
  exit 1
fi

node "$REPO_ROOT/test/switcher.test.mjs"
