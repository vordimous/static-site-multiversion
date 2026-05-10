# MkDocs example

A minimal MkDocs site that honors the [static-site-multiversion](../../README.md) builder contract.

This example demonstrates that the contract is not Node-specific: the same env vars wire into a Python build with no changes to the orchestrator.

## How the contract is wired

MkDocs reads its configuration from `mkdocs.yml` and doesn't natively consume env vars, so a thin shell wrapper ([build.sh](build.sh)) maps the contract onto the mkdocs CLI:

| Env var | MkDocs CLI flag | Meaning |
| --- | --- | --- |
| `SITE_VERSION_KEY` | part of `--site-dir` | URL slug for this version |
| `SITE_BASE` | part of `--site-dir` | optional path prefix |
| `DIST_DIR` | base of `--site-dir` | shared output root across versions |

Output lands at:

```
$DIST_DIR/[$SITE_BASE/]$SITE_VERSION_KEY/
```

## Running locally

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
SITE_VERSION_KEY=next ./build.sh
```

## Version switcher

MkDocs bakes the version dropdown into its native navbar at build time (via a generated `versions.yml` consumed by the theme) rather than mounting the shared client-side `switcher.js`. The dropdown is fully static, which fits MkDocs's no-JS-required model. If you want runtime discovery of new versions instead, swap to the shared shim by mounting `<div id="version-switcher" data-mode="hybrid">` in a custom template and dropping the bake step.

## Multi-version build

When invoking the orchestrator, point `BUILD_CMD` and `INSTALL_CMD` at this example's tooling:

```bash
INSTALL_CMD="pip install -r requirements.txt" \
BUILD_CMD="./build.sh" \
  scripts/build-versions.sh
```
