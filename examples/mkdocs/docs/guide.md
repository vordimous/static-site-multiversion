# Guide

This page exists so the build produces more than one route. Edit it freely when adapting the example.

## Build locally

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
SITE_VERSION_KEY=next ./build.sh
```

Output lands in `../../dist/next/` by default.
