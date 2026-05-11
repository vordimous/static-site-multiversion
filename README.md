# static-site-multiversion

A portable contract for building multi-version static sites from git tags, generator-agnostic. The live site contains the current `next` version at HEAD plus an arbitrary number of historical versions built from their original tags, merged into one deploy directory with a shared version switcher.

**The env-var protocol is the standard; the bash script is one reference implementation.** Any builder that honors three things (a `deploy-versions.json` file, two env vars, and an output convention) plugs in. This repo ships eight worked examples (plain HTML plus seven SSGs across three runtimes) as evidence that the contract holds.

> AI-assisted: I distilled this pattern from an existing VuePress v2 workflow that I built and ran in production for Aklivity's [zilla-docs](https://github.com/vordimous/zilla-docs). I used Claude to help draft the portable script, schema, and documentation. All content was reviewed for accuracy.

## Try the demo locally

The fastest way is the prebuilt image, which has every example × every demo version baked into nginx:

```bash
docker run --rm -p 8080:80 ghcr.io/vordimous/static-site-multiversion:latest
```

Then open [http://localhost:8080/]()

## The contract

Three pieces, none CI-specific or builder-specific.

### 1. `deploy-versions.json` at the repo root

A flat JSON array of versions to build alongside HEAD:

```json
[
  { "ref": "0.9.x", "key": "0.9" },
  { "ref": "1.0.x", "key": "1.0" }
]
```

`key` is the URL slug under which the version is served. `ref` is the git ref (tag or branch) to clone. See [schemas/deploy-versions.schema.json](./schemas/deploy-versions.schema.json).

Wire the schema into your editor for autocomplete and validation. In VS Code, add to `.vscode/settings.json`:

```json
{
  "json.schemas": [
    { "fileMatch": ["deploy-versions*.json"], "url": "./schemas/deploy-versions.schema.json" }
  ]
}
```

Or validate from the command line with [`ajv-cli`](https://github.com/ajv-validator/ajv-cli):

```bash
npx ajv validate -s schemas/deploy-versions.schema.json -d deploy-versions.json
```

#### Patch-version tags

Because `key` and `ref` are decoupled, you can ship a fix to an older version without changing the slug anyone has bookmarked. Tag the patched commit (e.g. `0.9.1`) and update `deploy-versions.json` so the `0.9` slug now resolves to it:

```json
[
  { "key": "0.9", "ref": "0.9.1" },
  { "key": "1.0", "ref": "1.0.2" }
  { "ref": "0.9.1", "key": "0.9" },
  { "ref": "1.0.2", "key": "1.0" },
  { "ref": "1.0.2", "key": "v1" },
  { "ref": "1.0.2", "key": "latest" }
]
```

The version dropdown still shows `0.9` and `1.0`. Deep links to `/0.9/...` keep working. The build comes from the latest patch tag. Useful when you need to backport a typo fix, add a new section, or, in this repo's own demo, retroactively include a new builder example in older docs (`demo-v0.9.1` adds vitepress to `demo-v0.9`'s tree without inventing a new slug).

By pointing more keys to the same `ref` you can make future proof canonical urls that won't break when you make updated. You may always want new users to land on the `latest` code, while a blog showcasing your version `1` features should point to the `v1` url. And the Roadmap for `1.0.x` changes should link to the `1.0` url.

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
<div id="version-switcher"
     data-mode="hybrid"
     data-canonical="/<base>/versions.json"
     data-fallback="/<base>/next/">
  <script type="application/json" id="version-switcher-seed">[{"key":"current","label":"current"}]</script>
</div>
<script src="./switcher.js" defer></script>
```

`data-canonical` and `data-fallback` should be absolute URL paths so the switcher works from nested pages (`/<builder>/<key>/sub/`). If both are omitted, the shim falls back to depth-0 relatives (`../versions.json`, `../next/`) which only resolve from each version's landing page.

The orchestrator copies `scripts/switcher.js` into every per-version output directory so each version's `<script src="./switcher.js">` resolves locally, no per-example asset wiring required.

#### Two integration styles

Examples integrate the switcher in one of two ways. Both are valid; pick whichever matches the generator you're using.

| Style | Examples | How it works |
| --- | --- | --- |
| Shared shim | `plain-html`, `eleventy`, `hugo`, `astro` | Page reserves a `<div id="version-switcher">` slot, loads `./switcher.js`, and the shim renders a `<select>` from the seed and/or canonical manifest at runtime. |
| Native navbar bake | `vitepress`, `vuepress`, `docusaurus`, `mkdocs` | The generator's own theme reads the canonical manifest (or `DEPLOY_VERSIONS` plus a `next` entry) at build time and emits the version dropdown straight into the rendered nav. No client JS from this repo. |

Native bake produces a JS-free dropdown that fits each generator's UX. The shared shim is generator-agnostic and gives you `runtime` / `hybrid` modes for live discovery of new versions added after a build was cached. If you want both (a baked dropdown that still updates with the latest list), use the shim's `hybrid` mode in addition to or in place of the bake.

### 3. The builder contract

Every builder honors two environment variables:

- `SITE_VERSION_KEY`: the slug being built (`next` for HEAD, otherwise a key from `deploy-versions.json`)
- `DIST_DIR`: a shared output root. The build writes to `$DIST_DIR/$SITE_VERSION_KEY/` (or `$DIST_DIR/$SITE_BASE/$SITE_VERSION_KEY/` when `SITE_BASE` is set)

Wiring those two vars into a generator is usually a few lines in its config. Each `examples/<builder>/` shows where.

## Build from source

This runs nginx, but rebuilds each example from this repo's own demo refs first:

```bash
scripts/demo-all.sh     # build every example × every demo version
scripts/demo-serve.sh   # host them on nginx at http://localhost:8080
```

`demo-all.sh` builds each `examples/<builder>/` along two version axes, merged into the same dropdown:

1. **Global demo timeline** ([deploy-versions.demo.json](deploy-versions.demo.json) at the repo root): the `demo-v0.9` and `demo-v1.0` tags plus the `demo-unstable` branch. These are this repo's own demo refs, and they exercise the full multi-version flow against a real git history.
2. **Per-builder refs** (`examples/<builder>/deploy-versions.json`): each builder's own generator-version tags (e.g. `eleventy-v3`, `hugo-v0-145`). The contract treats these like any other historical version, so a single dropdown can show both "0.9 / 1.0 / next" demo tags and "eleventy-v3 / eleventy-v2" generator tags.

Output lands in a shared docroot at `.demo/_serve/<builder>/<key>/`. `demo-serve.sh` runs `nginx:alpine` in docker against that docroot with a read-only bind mount, so re-running `demo-all.sh` updates the live site without restarting the container.

The landing page at `/` links into every built builder × version. Builders whose runtime toolchain (node, hugo, python + mkdocs) isn't installed locally are reported as skipped, not failed. Stop the container with `scripts/demo-serve.sh stop`.
The same multi-stage [Dockerfile](Dockerfile) is what the [release-image workflow](.github/workflows/release-image.yml) pushes to GHCR on every commit to the default branch.

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

## Tests

Run the suite with [`scripts/test.sh`](scripts/test.sh). It exercises [`scripts/build-versions.sh`](scripts/build-versions.sh) end-to-end against a synthetic git repo plus a smoke test for the plain-html example. The same suite runs on every push and pull request via [.github/workflows/test.yml](.github/workflows/test.yml), which also enforces `shellcheck` clean across `scripts/` and `test/`.

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

Two common URL layouts, both supported by the same orchestrator. `SITE_BASE` controls which one a given run produces:

| Layout | URL shape | How to produce |
| --- | --- | --- |
| Symmetric | `/<SITE_BASE>/<key>/...` for every version | One run with `SITE_BASE` set. Output lands under `$DIST_DIR/$SITE_BASE/<key>/`. |
| Promoted-next | `/...` for `next`, `/<SITE_BASE>/<key>/...` for older versions | Two runs: build HEAD with no `SITE_BASE` so `next/` lands at `$DIST_DIR/next/`, then run again with `SITE_BASE` set so historical versions land under `$DIST_DIR/$SITE_BASE/<key>/`. The deploy step uploads `$DIST_DIR` as a whole. |

Pick one layout per repo. Mixing them in the same deploy works but the version switcher's path-rewriting logic assumes a consistent shape, so deep links across versions need both old and new builds to share whichever layout you chose.

## Wanted

Each item below is a real contribution opportunity. See [CONTRIBUTING.md](CONTRIBUTING.md) for the step-by-step recipe (it's short).

- [ ] `ci/gitlab-ci.yml` reference
- [ ] `examples/next/` (Next.js with statically exported `output: 'export'`)
- [ ] `examples/nuxt/` (Nuxt with `nuxt generate`)
- [ ] `examples/sveltekit/` (SvelteKit with adapter-static)
- [ ] `examples/sphinx/` (Python docs, alternative to MkDocs)
- [ ] `examples/jekyll/` (Ruby, classic GitHub Pages)

## License

MIT (pending).
