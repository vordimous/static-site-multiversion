// Custom theme entry. Two extensions to the default theme:
// 1. style.css overrides the brand color to Vite indigo so VitePress is
//    visually distinct from the VuePress example.
// 2. The default Layout is wrapped to inject a custom <VersionDropdown>
//    into the `nav-bar-content-after` slot so the version switcher
//    becomes part of the native nav rather than a bolted-on element
//    at the bottom of the page.

import DefaultTheme from 'vitepress/theme'
import { h } from 'vue'
import VersionDropdown from './VersionDropdown.vue'
import './style.css'

export default {
  extends: DefaultTheme,
  Layout: () => {
    return h(DefaultTheme.Layout, null, {
      'nav-bar-content-after': () => h(VersionDropdown),
    })
  },
}
