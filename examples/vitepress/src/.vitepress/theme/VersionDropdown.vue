<script setup>
// Version dropdown rendered into VitePress's native nav via the
// `nav-bar-content-after` slot. The component handles its own runtime
// fetch (hybrid mode): it shows the seed list at build time, then
// replaces it with the canonical list from /<base>/versions.json.

import { ref, computed, onMounted, onUnmounted } from 'vue'

// Seed: what's known at build time. Replaced when the fetch resolves.
const versions = ref([{ key: 'current', label: 'current' }])
const open = ref(false)

// VitePress sets import.meta.env.BASE_URL to the build-time `base` config
// (e.g. /vitepress/next/). The per-builder root (one level up) is what we
// fetch versions.json from and what we link version slugs against.
const buildBase = import.meta.env.BASE_URL || '/'
const builderBase = buildBase.replace(/[^/]+\/$/, '') || '/'
const buildKey = (() => {
  const m = buildBase.match(/([^/]+)\/$/)
  return m ? m[1] : 'next'
})()

const baseAndKey = computed(() => {
  const segs = (typeof window === 'undefined' ? buildBase : window.location.pathname)
    .split('/')
    .filter(Boolean)
  const keys = versions.value.map(v => v.key)
  // Try to match the URL segment against a known key; otherwise fall back
  // to the build-time key (which the orchestrator put in the path).
  const idx = segs.findIndex(s => keys.includes(s))
  if (idx >= 0) {
    return {
      base: '/' + segs.slice(0, idx).join('/') + (idx === 0 ? '' : '/'),
      key: segs[idx],
    }
  }
  return { base: builderBase, key: buildKey }
})

const currentLabel = computed(() => {
  const { key } = baseAndKey.value
  const match = versions.value.find(v => v.key === key)
  return match ? (match.label || match.key) : key
})

function urlFor(key) {
  return `${baseAndKey.value.base}${key}/`
}

function close() {
  open.value = false
}

onMounted(async () => {
  document.addEventListener('click', close)
  try {
    const r = await fetch(`${baseAndKey.value.base}versions.json`, { cache: 'no-cache' })
    if (r.ok) {
      const data = await r.json()
      if (Array.isArray(data) && data.length) versions.value = data
    }
  } catch {
    // keep the seed
  }
})

onUnmounted(() => {
  document.removeEventListener('click', close)
})
</script>

<template>
  <div class="vp-version-menu" data-version-menu @click.stop>
    <button class="trigger" type="button" @click="open = !open">
      {{ currentLabel }}
      <span class="caret" aria-hidden="true">▾</span>
    </button>
    <div v-if="open" class="popover" role="menu">
      <a
        v-for="v in versions"
        :key="v.key"
        class="item"
        :href="urlFor(v.key)"
        :data-current="v.key === baseAndKey.key"
      >
        {{ v.label || v.key }}
      </a>
    </div>
  </div>
</template>

<style scoped>
.vp-version-menu {
  position: relative;
  display: flex;
  align-items: center;
  margin-left: 12px;
  padding-left: 12px;
  border-left: 1px solid var(--vp-c-divider);
  height: var(--vp-nav-height);
}
.trigger {
  background: none;
  border: none;
  padding: 0 8px;
  font-size: 14px;
  font-weight: 500;
  color: var(--vp-c-text-1);
  cursor: pointer;
  transition: color 0.25s;
}
.trigger:hover { color: var(--vp-c-brand-1); }
.caret {
  font-size: 10px;
  margin-left: 2px;
  color: var(--vp-c-text-2);
}
.popover {
  position: absolute;
  top: calc(var(--vp-nav-height) - 4px);
  right: 0;
  min-width: 140px;
  padding: 6px 0;
  background: var(--vp-c-bg);
  border: 1px solid var(--vp-c-divider);
  border-radius: 8px;
  box-shadow: 0 4px 14px rgba(0, 0, 0, 0.08);
  z-index: 50;
}
.item {
  display: block;
  padding: 6px 16px;
  font-size: 14px;
  color: var(--vp-c-text-1);
  text-decoration: none;
  white-space: nowrap;
}
.item:hover {
  color: var(--vp-c-brand-1);
  background: var(--vp-c-bg-soft);
}
.item[data-current="true"] {
  font-weight: 600;
  color: var(--vp-c-brand-1);
}
</style>
