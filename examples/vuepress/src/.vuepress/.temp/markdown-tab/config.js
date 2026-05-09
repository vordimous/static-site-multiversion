import { CodeTabs } from "/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/node_modules/@vuepress/plugin-markdown-tab/dist/client/components/CodeTabs.js";
import { Tabs } from "/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/node_modules/@vuepress/plugin-markdown-tab/dist/client/components/Tabs.js";

export default {
  enhance: ({ app }) => {
    app.component("CodeTabs", CodeTabs);
    app.component("Tabs", Tabs);
  },
};
