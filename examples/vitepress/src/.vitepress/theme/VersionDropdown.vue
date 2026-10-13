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
// (e.g. /vitepress/next/). Its last segment is this build's version key and
// the rest is the per-builder root that holds versions.json and every
// version dir. Reading both from the build rather than matching URL segments
// against keys stays correct when SITE_BASE or a page slug equals a key.
const buildBase = import.meta.env.BASE_URL || '/'
const builderBase = buildBase.replace(/[^/]+\/$/, '') || '/'
const buildKey = buildBase.match(/([^/]+)\/$/)?.[1] ?? 'next'

const currentLabel = computed(() => {
  const match = versions.value.find(v => v.key === buildKey)
  return match ? (match.label || match.key) : buildKey
})

function urlFor(key) {
  return `${builderBase}${key}/`
}

function close() {
  open.value = false
}

onMounted(async () => {
  document.addEventListener('click', close)
  try {
    const r = await fetch(`${builderBase}versions.json`, { cache: 'no-cache' })
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
    <!-- target="_self" opts the links out of VitePress's client router, which
         would otherwise resolve another version's URL inside this build and
         render its 404 page. -->
    <div v-if="open" class="popover" role="menu">
      <a
        v-for="v in versions"
        :key="v.key"
        class="item"
        :href="urlFor(v.key)"
        target="_self"
        :data-current="v.key === buildKey"
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
