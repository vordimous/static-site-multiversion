# Contributing

The most useful contribution is a new builder example. Each one demonstrates how to wire a different static-site generator into the [builder contract](README.md#the-contract).

## Adding a builder example

1. Create `examples/<builder>/` with a minimal site (a homepage and one other route is enough).
2. Wire `SITE_VERSION_KEY`, optional `SITE_BASE`, and `DIST_DIR` from environment variables into whichever options control the generator's output directory and URL prefix. The end result must be that the build writes to `$DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/` with internal links and asset URLs that work when deployed under that path.
3. Verify locally by running the build twice: once with `SITE_VERSION_KEY=next` and no `SITE_BASE`, once with both `SITE_VERSION_KEY` and `SITE_BASE` set. Confirm the output paths match the contract in both cases.
4. Add an `examples/<builder>/README.md` that documents the wiring, the build command, and any quirks of the generator (for example, MkDocs needs a wrapper script because it doesn't read env vars natively).
5. Add an `examples/<builder>/deploy-versions.json` file (start with `[]`). This is the per-builder version axis used by `scripts/demo-all.sh`; populate it with this builder's own real generator-version tags (e.g. `eleventy-v3`, `hugo-v0-145`) when those tags exist.
6. Update the top-level `README.md` to list the new example under "Worked examples" and remove it from "Wanted" if applicable.

## Adding a CI provider example

`ci/<provider>.yml` (or whatever extension fits) should be a thin wrapper that does three things:

1. Caches `$DIST_DIR` keyed on `hash(deploy-versions.json)`. Historical builds are immutable so a cache hit lets the workflow skip them.
2. Invokes `scripts/build-versions.sh` with whatever toolchain setup the chosen example builders need.
3. Uploads or deploys `$DIST_DIR` to the provider's static-host of choice.

Keep wrappers minimal. Logic that isn't provider-specific belongs in `scripts/build-versions.sh`, not duplicated across CI files.

## Tests

Run the suite with:

```bash
scripts/test.sh
```

It exercises `scripts/build-versions.sh` against a synthetic git repo using `test/fake-build.sh` as the builder. New tests go under `test/test-*.sh` and are picked up automatically.

`shellcheck scripts/*.sh test/*.sh` should pass clean before merging.

## Code style

- Bash: `set -euo pipefail` at the top, quote all expansions, prefer subshells for env scoping.
- Markdown and prose: no em dashes or `--` as clause separators. Don't insert hard wraps for line-length reasons; let editors wrap.
