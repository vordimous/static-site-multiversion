export const redirects = JSON.parse("{}")

export const routes = Object.fromEntries([
  ["/", { loader: () => import(/* webpackChunkName: "index.html" */"/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/src/README.md"), meta: {"title":""} }],
  ["/guide/", { loader: () => import(/* webpackChunkName: "guide_index.html" */"/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/src/guide/README.md"), meta: {"title":"Guide"} }],
  ["/guide/getting-started.html", { loader: () => import(/* webpackChunkName: "guide_getting-started.html" */"/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/src/guide/getting-started.md"), meta: {"title":"Getting started"} }],
  ["/404.html", { loader: () => import(/* webpackChunkName: "404.html" */"/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/src/.vuepress/.temp/pages/404.html.vue"), meta: {"title":""} }],
]);
