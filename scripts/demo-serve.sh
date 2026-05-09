#!/usr/bin/env bash
#
# Hosts the local multi-version demo (built by scripts/demo-all.sh) on
# nginx:alpine via docker. The .demo/_serve/ tree is mounted read-only at
# /usr/share/nginx/html, so changes from re-running demo-all.sh show up
# immediately without restarting the container.
#
# Usage:
#   scripts/demo-serve.sh            # start (default port 8080)
#   PORT=9000 scripts/demo-serve.sh  # start on custom port
#   scripts/demo-serve.sh stop       # stop and remove the container

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVE_ROOT="$REPO_ROOT/.demo/_serve"
CONTAINER="ssm-demo"
PORT="${PORT:-8080}"

case "${1:-up}" in
  up|start|"")
    command -v docker >/dev/null || { echo "demo-serve: docker not found. Install Docker Desktop, or serve $SERVE_ROOT with any static server (e.g. python3 -m http.server -d $SERVE_ROOT 8080)." >&2; exit 1; }
    [ -d "$SERVE_ROOT" ] || { echo "demo-serve: $SERVE_ROOT not found. Run scripts/demo-all.sh first." >&2; exit 1; }
    if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
      echo "demo-serve: $CONTAINER already running on port $PORT"
    else
      docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
      docker run -d --rm \
        --name "$CONTAINER" \
        -p "$PORT:80" \
        -v "$SERVE_ROOT:/usr/share/nginx/html:ro" \
        nginx:alpine >/dev/null
      echo "demo-serve: started $CONTAINER"
    fi
    echo "demo-serve: open http://localhost:$PORT/"
    ;;
  stop|down)
    if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
      docker stop "$CONTAINER" >/dev/null
      echo "demo-serve: stopped $CONTAINER"
    else
      echo "demo-serve: $CONTAINER not running"
    fi
    ;;
  *)
    echo "usage: scripts/demo-serve.sh [up|stop]" >&2
    exit 2
    ;;
esac
