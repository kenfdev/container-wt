#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Switch the active Traefik route to a specific worktree's app container.
# Rewrites .worktree/traefik/dynamic.yml; Traefik reloads it automatically.
#
# Usage: .worktree/switch-branch.sh <worktree-name> [app-port]
#   worktree-name  — the WORKTREE_NAME value (see .worktree/.env for each worktree)
#   app-port       — port the app listens on inside the container (default: 3000)
# =============================================================================

WORKTREE_NAME="${1:?Usage: switch-branch.sh <worktree-name> [app-port]}"
APP_PORT="${2:-3000}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_REPO_DIR="$(dirname "$SCRIPT_DIR")"
DYNAMIC_YML="${SCRIPT_DIR}/traefik/dynamic.yml"

# Load PROJECT_NAME from the root .env written by init.sh.
if [[ -f "${MAIN_REPO_DIR}/.env" ]]; then
  # shellcheck source=/dev/null
  source "${MAIN_REPO_DIR}/.env"
fi
PROJECT_NAME="${PROJECT_NAME:-$(basename "$MAIN_REPO_DIR")}"

CONTAINER_NAME="app-${PROJECT_NAME}-${WORKTREE_NAME}"

mkdir -p "${SCRIPT_DIR}/traefik"

cat > "$DYNAMIC_YML" <<EOF
# Active branch routing for localhost:${APP_PORT}
# Managed by .worktree/switch-branch.sh — do not edit manually.
http:
  routers:
    active-app:
      rule: "PathPrefix(\`/\`)"
      service: active-app
      entrypoints:
        - localport
  services:
    active-app:
      loadBalancer:
        servers:
          - url: "http://${CONTAINER_NAME}:${APP_PORT}"
EOF

echo "[container-wt] Active branch switched to '${WORKTREE_NAME}' → ${CONTAINER_NAME}:${APP_PORT}"
