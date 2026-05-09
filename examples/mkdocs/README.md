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

## Multi-version build

When invoking the orchestrator, point `BUILD_CMD` and `INSTALL_CMD` at this example's tooling:

```bash
INSTALL_CMD="pip install -r requirements.txt" \
BUILD_CMD="./build.sh" \
  scripts/build-versions.sh
```
