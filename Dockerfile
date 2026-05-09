# syntax=docker/dockerfile:1.6
#
# Multi-stage image that bakes every example x every demo version into
# nginx:alpine. The builder stage runs scripts/demo-all.sh to produce the
# shared docroot at .demo/_serve/, and the runtime stage just hosts it.
#
# A local `docker build .` reproduces what the GHCR workflow ships, given a
# checkout that has the demo-* tags and the demo-unstable branch as local
# refs (CI does this via `git fetch origin '+refs/heads/*:refs/heads/*'`
# after actions/checkout with fetch-depth: 0).

FROM node:20-bookworm AS builder

ARG HUGO_VERSION=0.145.0
# Space-separated builder names, or empty for "all". Mostly useful for
# trimming local test builds (e.g. --build-arg BUILDERS=plain-html).
ARG BUILDERS=""
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash git jq python3 python3-pip python3-venv ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

RUN arch="$(dpkg --print-architecture)" \
 && curl -fsSL "https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_extended_${HUGO_VERSION}_linux-${arch}.tar.gz" \
    | tar -xz -C /usr/local/bin hugo \
 && hugo version

RUN python3 -m venv /opt/mkdocs \
 && /opt/mkdocs/bin/pip install --no-cache-dir mkdocs
# Put the venv first on PATH so demo-all.sh's `command -v python3` and
# `python3 -c 'import mkdocs'` both resolve to the venv interpreter.
ENV PATH="/opt/mkdocs/bin:${PATH}"

WORKDIR /src
COPY . .

# build-versions.sh clones $REPO_URL=file:///src per version, so we need a
# real .git with the demo-* refs as local branches/tags. Validate up front
# so the build fails with a clear message instead of mid-clone.
RUN git -C /src rev-parse demo-v0.9 demo-v1.0 demo-unstable >/dev/null

# shellcheck disable=SC2086  # word-splitting BUILDERS into argv is intentional
RUN scripts/demo-all.sh ${BUILDERS}


FROM nginx:alpine

LABEL org.opencontainers.image.title="static-site-multiversion demo"
LABEL org.opencontainers.image.description="Every example x every demo version, hosted on nginx."
LABEL org.opencontainers.image.source="https://github.com/vordimous/static-site-multiversion"
LABEL org.opencontainers.image.licenses="MIT"

COPY --from=builder /src/.demo/_serve /usr/share/nginx/html
