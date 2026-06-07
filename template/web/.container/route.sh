#!/usr/bin/env bash
set -euo pipefail

# Route http://localhost:${TRAEFIK_PORT} to one running worktree app container.
# Run from any worktree root.

usage() {
  cat <<'EOF'
Usage:
  .container/route.sh
  .container/route.sh <worktree-name>
  .container/route.sh <worktree-name> <app-port>
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [ ! -f ".container/.env" ]; then
  echo "[container-wt] Missing .container/.env. Run .container/init.sh first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source ".container/.env"

TARGET_WORKTREE="${1:-$WORKTREE_NAME}"
TARGET_PORT="${2:-$APP_PORT}"
CONTAINER_NAME="app-${PROJECT_NAME}-${TARGET_WORKTREE}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "[container-wt] Container ${CONTAINER_NAME} is not running." >&2
  echo "[container-wt] Start it with:" >&2
  echo "  cd .container && docker compose up -d --build" >&2
  exit 1
fi

gitdir=$(git rev-parse --git-common-dir)
case "$gitdir" in
  /*) ;;
  *) gitdir="$PWD/$gitdir" ;;
esac
GIT_COMMON_DIR=$(cd "$gitdir" && pwd)
MAIN_REPO_DIR=$(dirname "$GIT_COMMON_DIR")

TRAEFIK_PORT="${TRAEFIK_PORT:-9876}"
if [ -f "${MAIN_REPO_DIR}/.env" ]; then
  root_traefik_port=$(grep -E '^TRAEFIK_PORT=' "${MAIN_REPO_DIR}/.env" 2>/dev/null \
    | tail -n 1 \
    | cut -d= -f2- \
    | sed 's/^["'\'']//; s/["'\'']$//' || true)
  if [ -n "$root_traefik_port" ]; then
    TRAEFIK_PORT="$root_traefik_port"
  fi
fi
TRAEFIK_PORT="${TRAEFIK_PORT:-9876}"

DYNAMIC_DIR="${MAIN_REPO_DIR}/.container/traefik"
DYNAMIC_YML="${DYNAMIC_DIR}/dynamic.yml"
mkdir -p "$DYNAMIC_DIR"

cat > "$DYNAMIC_YML" <<EOF
# Managed by .container/route.sh. Do not edit manually.
http:
  routers:
    active-app:
      rule: "PathPrefix(\`/\`)"
      service: active-app
      entrypoints:
        - web
  services:
    active-app:
      loadBalancer:
        servers:
          - url: "http://${CONTAINER_NAME}:${TARGET_PORT}"
EOF

echo "[container-wt] http://localhost:${TRAEFIK_PORT} -> ${CONTAINER_NAME}:${TARGET_PORT}"
