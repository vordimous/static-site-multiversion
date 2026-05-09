# static-site-multiversion

A portable contract for building multi-version static sites from git tags, generator-agnostic. The live site contains the current `next` version at HEAD plus an arbitrary number of historical versions built from their original tags, merged into one deploy directory with a shared version switcher.

**The env-var protocol is the standard; the bash script is one reference implementation.** Any builder that honors three things (a `deploy-versions.json` file, two env vars, and an output convention) plugs in. This repo ships seven worked examples (plain HTML plus six SSGs across three runtimes) as evidence that the contract holds.

> AI-assisted: I distilled this pattern from an existing VuePress workflow (Aklivity's [zilla-docs](https://github.com/aklivity/zilla-docs)) and used Claude to help draft the portable script, schema, and documentation. All content was reviewed for accuracy.

## Try the demo locally

Clone the repo, then from the repo root:

```bash
scripts/demo-all.sh     # build every example × every demo version
scripts/demo-serve.sh   # host them on nginx at http://localhost:8080
```

`demo-all.sh` builds each `examples/<builder>/` against this repo's own `demo-v0.9` / `demo-v1.0` tags and the `demo-unstable` branch (configured in [deploy-versions.demo.json](deploy-versions.demo.json)) into a shared docroot at `.demo/_serve/<builder>/<key>/`. `demo-serve.sh` runs `nginx:alpine` in docker against that docroot with a read-only bind mount, so re-running `demo-all.sh` updates the live site without restarting the container.

The landing page at `/` links into every built builder × version. Builders whose runtime toolchain (node, hugo, python + mkdocs) isn't installed locally are reported as skipped, not failed. Stop the container with `scripts/demo-serve.sh stop`.

## The contract

Three pieces, none CI-specific or builder-specific.

### 1. `deploy-versions.json` at the repo root

A flat JSON array of versions to build alongside HEAD:

```json
[
  { "key": "0.9", "tag": "0.9.x" },
  { "key": "1.0", "tag": "1.0.x" }
]
```

`key` is the URL slug under which the version is served. `tag` is the git ref to clone. See [schemas/deploy-versions.schema.json](schemas/deploy-versions.schema.json).

### 2. The version-switcher manifest

Whatever your site reads at build time to render its version dropdown. Default location: `src/versions.json`. The orchestration generates it by merging your site's own list with `deploy-versions.json` and copies it into each historical clone before that clone builds.

### 3. The builder contract

Every builder honors two environment variables:

- `SITE_VERSION_KEY`: the slug being built (`next` for HEAD, otherwise a key from `deploy-versions.json`)
- `DIST_DIR`: a shared output root. The build writes to `$DIST_DIR/$SITE_VERSION_KEY/` (or `$DIST_DIR/$SITE_BASE/$SITE_VERSION_KEY/` when `SITE_BASE` is set)

Wiring those two vars into a generator is usually a few lines in its config. Each `examples/<builder>/` shows where.

## Worked examples

Seven examples, each verified building both URL layouts locally:

| Example | Runtime | Notable for |
| --- | --- | --- |
| [`examples/plain-html/`](examples/plain-html/) | None (just bash) | The contract, distilled. The build is `cp`. |
| [`examples/vuepress/`](examples/vuepress/) | Node | Vue-based docs, the source pattern |
| [`examples/astro/`](examples/astro/) | Node | General-purpose, content-collections |
| [`examples/docusaurus/`](examples/docusaurus/) | Node (React) | React-based docs (Meta) |
| [`examples/eleventy/`](examples/eleventy/) | Node | Minimal SSG, no shell wrapper needed |
| [`examples/hugo/`](examples/hugo/) | Go | Single binary, fastest builds |
| [`examples/mkdocs/`](examples/mkdocs/) | Python | Cross-runtime proof of portability |

Start with `examples/plain-html/` if you want to see the contract on its own; pick the example matching your generator if you want to see real wiring. Or run [`scripts/demo-all.sh`](scripts/demo-all.sh) and browse them all side-by-side under nginx (see "Try the demo locally" above).

## The portable orchestration

[scripts/build-versions.sh](scripts/build-versions.sh) is one reference implementation of the contract. It runs the full multi-version build using only `bash`, `git`, and `jq`. It works locally and in any CI provider. Usage:

```bash
REPO_URL=https://github.com/you/your-site.git \
  scripts/build-versions.sh
```

Optional overrides documented in the script header. You can replace this script with any equivalent orchestrator (Make, a Go binary, a Node script) as long as it honors the contract — the env-var protocol is what builders rely on, not the script itself.

## Why this exists

When you publish a versioned static site, you typically want one deploy that contains:

- The current docs (built from HEAD on the deploy branch)
- One or more older versions built from their original git tags, so deep links to old docs keep working

Doing this naively means a separate site per version with manual cross-linking. Doing it well means one CI job that knows how to check out each tag, build it, and merge the outputs into a single deployable directory, with a shared version switcher. Existing tools (Docusaurus's built-in versioning, MkDocs's `mike`, `sphinx-multiversion`) each solve this for one generator. This repo captures the pattern as a portable contract any generator can satisfy.

## CI integration

Each provider needs a thin wrapper that:

1. Caches `$DIST_DIR` keyed by `hash(deploy-versions.json)`. Historical builds are immutable, so a cache hit skips them entirely and only HEAD rebuilds.
2. Runs `scripts/build-versions.sh`.
3. Uploads or deploys `$DIST_DIR`.

Reference wrappers live under [ci/](ci/). Start with [ci/github-actions.yml](ci/github-actions.yml).

## Routing conventions

Two common URL layouts, both supported by the same build:

| Layout | URL shape | When to use |
| --- | --- | --- |
| Symmetric | `/<SITE_BASE>/<key>/...` for every version | GitHub Pages projects, anything served under a path prefix |
| Promoted-next | `/...` for `next`, `/<SITE_BASE>/<key>/...` for older versions | Custom domains where the latest docs live at the apex |

The orchestration produces both layouts in `$DIST_DIR`. The deploy step picks which subset to publish.

## Wanted

- [ ] `ci/gitlab-ci.yml` reference
- [ ] `examples/next/` (Next.js with statically exported `output: 'export'`)
- [ ] `examples/nuxt/` (Nuxt with `nuxt generate`)
- [ ] `examples/sveltekit/` (SvelteKit with adapter-static)
- [ ] `examples/sphinx/` (Python docs, alternative to MkDocs)
- [ ] `examples/jekyll/` (Ruby, classic GitHub Pages)

## License

MIT (pending).
