# versioned-jamstack-examples

A portable pattern for building and deploying multi-version Jamstack sites (docs, marketing, anything static) where the live site contains the current `next` version at HEAD plus an arbitrary number of historical versions built from git tags.

The intent of this repo is to be a living reference. The core orchestration is a single shell script and a small contract that any static-site generator can satisfy. Each `examples/<builder>/` directory shows how to wire one specific generator (VuePress, Docusaurus, Astro, MkDocs, Next, etc.) into the contract.

> AI-assisted: I distilled this pattern from an existing VuePress workflow (Aklivity's [zilla-docs](https://github.com/aklivity/zilla-docs)) and used Claude to help draft the portable script, schema, and documentation. All content was reviewed for accuracy.

## What problem this solves

When you publish a versioned static site, you typically want one deploy that contains:

- The current docs (built from HEAD on the deploy branch)
- One or more older versions built from their original git tags, so deep links to old docs keep working

Doing this naively means a separate site per version with manual cross-linking. Doing it well means one CI job that knows how to check out each tag, build it, and merge the outputs into a single deployable directory, with a shared version switcher.

This repo captures the "doing it well" version as something portable across CI providers and static-site generators.

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

Whatever your site reads at build time to render its version dropdown. Default location: `src/versions.json`. The orchestration script generates it by merging your site's own list with `deploy-versions.json` and copies it into each historical clone before that clone builds.

### 3. The builder contract

Every builder example in this repo honors two environment variables:

- `SITE_VERSION_KEY`: the slug being built (`next` for HEAD, otherwise a key from `deploy-versions.json`)
- `DIST_DIR`: a shared output root. The build writes to `$DIST_DIR/$SITE_VERSION_KEY/` (or `$DIST_DIR/$SITE_BASE/$SITE_VERSION_KEY/` when `SITE_BASE` is set)

Wiring those two vars into a generator is usually a few lines in its config. Each `examples/<builder>/` shows where.

## The portable orchestration

[scripts/build-versions.sh](scripts/build-versions.sh) runs the full multi-version build using only `bash`, `git`, and `jq`. It works locally and in any CI provider. Usage:

```bash
REPO_URL=https://github.com/you/your-site.git \
  scripts/build-versions.sh
```

Optional overrides documented in the script header.

## CI integration

Each provider needs a thin wrapper that:

1. Caches `$DIST_DIR` keyed by `hash(deploy-versions.json)`. Historical builds are immutable, so a cache hit skips them entirely and only HEAD rebuilds.
2. Runs `scripts/build-versions.sh`.
3. Uploads or deploys `$DIST_DIR`.

Reference wrappers live under [ci/](ci/). Start with [ci/github-actions.yml](ci/github-actions.yml).

## What's here

- [x] `scripts/build-versions.sh` (portable core, end-to-end tested)
- [x] `schemas/deploy-versions.schema.json`
- [x] `ci/github-actions.yml` reference

Six builder examples, each verified building both URL layouts locally:

| Example | Runtime | Notable for |
| --- | --- | --- |
| [`examples/vuepress/`](examples/vuepress/) | Node | Vue-based docs, the source pattern |
| [`examples/astro/`](examples/astro/) | Node | General-purpose, content-collections |
| [`examples/docusaurus/`](examples/docusaurus/) | Node (React) | React-based docs (Meta) |
| [`examples/eleventy/`](examples/eleventy/) | Node | Minimal SSG, no shell wrapper needed |
| [`examples/hugo/`](examples/hugo/) | Go | Single binary, fastest builds |
| [`examples/mkdocs/`](examples/mkdocs/) | Python | Cross-runtime proof of portability |

## Wanted

- [ ] `ci/gitlab-ci.yml` reference
- [ ] `examples/next/` (Next.js with statically exported `output: 'export'`)
- [ ] `examples/nuxt/` (Nuxt with `nuxt generate`)
- [ ] `examples/sveltekit/` (SvelteKit with adapter-static)
- [ ] `examples/sphinx/` (Python docs, alternative to MkDocs)
- [ ] `examples/jekyll/` (Ruby, classic GitHub Pages)

## Routing conventions

Two common URL layouts, both supported by the same build:

| Layout | URL shape | When to use |
| --- | --- | --- |
| Symmetric | `/<SITE_BASE>/<key>/...` for every version | GitHub Pages projects, anything served under a path prefix |
| Promoted-next | `/...` for `next`, `/<SITE_BASE>/<key>/...` for older versions | Custom domains where the latest docs live at the apex |

The orchestration produces both layouts in `$DIST_DIR`. The deploy step picks which subset to publish.

## License

MIT (pending).
