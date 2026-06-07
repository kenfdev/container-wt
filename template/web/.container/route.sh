#!/usr/bin/env bash
set -euo pipefail

# Route http://localhost:${TRAEFIK_PORT} to one running worktree app container.
# Run from anywhere inside the repository/worktree.

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

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKTREE_ROOT=$(dirname "$SCRIPT_DIR")
CONTAINER_DIR="${WORKTREE_ROOT}/.container"

cd "$WORKTREE_ROOT"

if [ ! -f "${CONTAINER_DIR}/.env" ]; then
  echo "[container-wt] Missing .container/.env. Run .container/init.sh first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${CONTAINER_DIR}/.env"

TARGET_WORKTREE="${1:-$WORKTREE_NAME}"
TARGET_PORT="${2:-$APP_PORT}"
CONTAINER_NAME="app-${PROJECT_NAME}-${TARGET_WORKTREE}"
TRAEFIK_CONTAINER="traefik-${PROJECT_NAME}"

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

if ! docker ps --format '{{.Names}}' | grep -qx "$TRAEFIK_CONTAINER"; then
  echo "[container-wt] Traefik container ${TRAEFIK_CONTAINER} is not running." >&2
  echo "[container-wt] Start infra with:" >&2
  echo "  docker compose up -d" >&2
  exit 1
fi

# Docker Desktop for Mac can miss fsnotify events for bind-mounted files.
# Restart Traefik after changing the file-provider config so the route switch
# is deterministic.
docker restart "$TRAEFIK_CONTAINER" >/dev/null

echo "[container-wt] http://localhost:${TRAEFIK_PORT} -> ${CONTAINER_NAME}:${TARGET_PORT}"
