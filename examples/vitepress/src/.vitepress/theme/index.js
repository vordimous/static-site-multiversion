// Custom theme entry — re-exports the default theme and pulls in a CSS
// override so VitePress shows up in the Vite brand purple instead of the
// default green, distinguishing it from the VuePress example at a glance.

import DefaultTheme from 'vitepress/theme'
import './style.css'

export default DefaultTheme
