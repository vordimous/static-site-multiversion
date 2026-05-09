import { GitContributors } from "/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/node_modules/@vuepress/plugin-git/dist/client/components/GitContributors.js";
import { GitChangelog } from "/Users/ajdanelz/Code/static-site-multiversion/examples/vuepress/node_modules/@vuepress/plugin-git/dist/client/components/GitChangelog.js";

export default {
  enhance: ({ app }) => {
    app.component("GitContributors", GitContributors);
    app.component("GitChangelog", GitChangelog);
  },
};
