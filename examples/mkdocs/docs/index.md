# Cross-runtime proof of portability.

MkDocs is a Python static site generator. It doesn't natively read environment variables, so the contract wiring is a thin shell wrapper (`build.sh`) that maps `SITE_VERSION_KEY` / `SITE_BASE` / `DIST_DIR` to MkDocs CLI flags. The version slug is supplied at build time via the `SITE_VERSION_KEY` environment variable.

Demo build marker: **next**

- [Read the guide](guide.md)
