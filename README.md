# static-site-multiversion

A portable contract for building multi-version static sites from git tags, generator-agnostic. The live site contains the current `next` version at HEAD plus an arbitrary number of historical versions built from their original tags, merged into one deploy directory with a shared version switcher.

**The env-var protocol is the standard; the bash script is one reference implementation.** Any builder that honors three things (a `deploy-versions.json` file, two env vars, and an output convention) plugs in. This repo ships eight worked examples (plain HTML plus seven SSGs across three runtimes) as evidence that the contract holds.

> AI-assisted: I distilled this pattern from an existing VuePress workflow (Aklivity's [zilla-docs](https://github.com/aklivity/zilla-docs)) and used Claude to help draft the portable script, schema, and documentation. All content was reviewed for accuracy.

## Try the demo locally

The fastest way is the prebuilt image, which has every example × every demo version baked into nginx:

```bash
docker run --rm -p 8080:80 ghcr.io/vordimous/static-site-multiversion:latest
# open http://localhost:8080/
```

Or build from source (also runs nginx, but rebuilds each example from this repo's own demo refs first):

```bash
scripts/demo-all.sh     # build every example × every demo version
scripts/demo-serve.sh   # host them on nginx at http://localhost:8080
```

`demo-all.sh` builds each `examples/<builder>/` along two axes of versioning, merged at runtime: the global demo timeline ([deploy-versions.demo.json](deploy-versions.demo.json) at the repo root, with `demo-v0.9` / `demo-v1.0` tags and the `demo-unstable` branch) and each builder's own per-example refs (`examples/<builder>/deploy-versions.json`, used to anchor real generator-version tags like `eleventy-v3` or `hugo-v0-145`). Output lands in a shared docroot at `.demo/_serve/<builder>/<key>/`. `demo-serve.sh` runs `nginx:alpine` in docker against that docroot with a read-only bind mount, so re-running `demo-all.sh` updates the live site without restarting the container.

The landing page at `/` links into every built builder × version. Builders whose runtime toolchain (node, hugo, python + mkdocs) isn't installed locally are reported as skipped, not failed. Stop the container with `scripts/demo-serve.sh stop`.

The same multi-stage [Dockerfile](Dockerfile) is what the [release-image workflow](.github/workflows/release-image.yml) pushes to GHCR on every commit to the default branch.

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

#### Patch-version tags

Because `key` and `tag` are decoupled, you can ship a fix to an older version without changing the slug anyone has bookmarked. Tag the patched commit (e.g. `0.9.1`) and update `deploy-versions.json` so the `0.9` slug now resolves to it:

```json
[
  { "key": "0.9", "tag": "0.9.1" },
  { "key": "1.0", "tag": "1.0.2" }
]
```

The version dropdown still shows `0.9` and `1.0`. Deep links to `/0.9/...` keep working. The build comes from the latest patch tag. Useful when you need to backport a typo fix, add a new section, or, in this repo's own demo, retroactively include a new builder example in older docs (`demo-v0.9.1` adds vitepress to `demo-v0.9`'s tree without inventing a new slug).

Patch tags pair especially well with the **runtime** and **hybrid** switcher modes: the dropdown in already-cached old versions reflects the new patch list as soon as the canonical `versions.json` is republished, with no rebuild.

### 2. The version-switcher manifest

Each example commits a `src/versions.json` (the **seed**) that snapshots whatever versions were known at build time. This is what the page can render synchronously without any network access — the noscript-friendly fallback.

After every per-version build finishes, the orchestrator publishes the **canonical** merged list (deploy-versions + a `next` entry for HEAD) at `$DIST_DIR/[$SITE_BASE/]versions.json`. The version-switcher shim fetches this file at runtime so old versions can discover newer ones added after their own build was cached.

#### Switcher modes

The shared shim at [scripts/switcher.js](scripts/switcher.js) supports three modes via `data-mode` on its mount element:

| Mode | Behavior | Use when |
| --- | --- | --- |
| `baked` | Render only from the inline JSON seed at build time. No fetch. | You want old versions frozen — historical docs never auto-discover new releases. |
| `runtime` | Ignore the seed. Fetch the canonical list and render from that. Show the `data-fallback` "View all versions" link if the fetch fails. | You always want the live list, accept that JS is required. |
| `hybrid` | Render the seed first (works without network), then fetch the canonical list and replace the dropdown if it differs. Falls back to the seed on fetch failure. | Default. Best of both — works offline, updates live. |

Mount template:

```html
<div id="version-switcher" data-mode="hybrid" data-fallback="../next/">
  <script type="application/json" id="version-switcher-seed">[{"key":"current","label":"current"}]</script>
</div>
<script src="./switcher.js" defer></script>
```

`data-canonical="/<base>/versions.json"` and `data-fallback="/<base>/next/"` accept absolute URLs for nested pages where relative paths break.

The orchestrator copies `scripts/switcher.js` into every per-version output directory so each version's `<script src="./switcher.js">` resolves locally — no per-example asset wiring required.

### 3. The builder contract

Every builder honors two environment variables:

- `SITE_VERSION_KEY`: the slug being built (`next` for HEAD, otherwise a key from `deploy-versions.json`)
- `DIST_DIR`: a shared output root. The build writes to `$DIST_DIR/$SITE_VERSION_KEY/` (or `$DIST_DIR/$SITE_BASE/$SITE_VERSION_KEY/` when `SITE_BASE` is set)

Wiring those two vars into a generator is usually a few lines in its config. Each `examples/<builder>/` shows where.

## Worked examples

Eight examples, each verified building both URL layouts locally:

| Example | Runtime | Notable for |
| --- | --- | --- |
| [`examples/plain-html/`](examples/plain-html/) | None (just bash) | The contract, distilled. The build is `cp`. |
| [`examples/vuepress/`](examples/vuepress/) | Node | Vue-based docs, the source pattern |
| [`examples/vitepress/`](examples/vitepress/) | Node | Vite-powered Vue 3 docs, fast incremental builds |
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

1. Restores the SHA-keyed artifact cache (see below).
2. Runs `scripts/build-versions.sh`.
3. Saves the cache.
4. Uploads or deploys `$DIST_DIR`.

Reference wrappers live under [ci/](ci/). Start with [ci/github-actions.yml](ci/github-actions.yml).

### SHA-keyed artifact cache

Set `CACHE_DIR=/some/path` and `scripts/build-versions.sh` will, for each entry in `deploy-versions.json`:

1. Resolve the tag's commit SHA via `git ls-remote`.
2. Look for `$CACHE_DIR/<sha>/<key>/index.html`.
3. **Cache hit** → restore that directory into `$DIST_DIR/[$SITE_BASE/]<key>/`. Skip clone + build entirely.
4. **Cache miss** → clone, build, copy result into the cache.

`HEAD` (the `next` build) and any moving branch tip always rebuild because their commit SHAs change every time. Tags never move, so once built they're cached forever.

In `actions/cache@v4`, key the cache on the repo + a manual bump: the SHA is in the path so per-tag keys aren't needed. To bust the cache, delete `$CACHE_DIR/<sha>/`.

Combined with the runtime switcher, this lets you ship updates to `next` without touching any historical version's static output, and add a brand-new tag without rebuilding any prior tag's output.

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
