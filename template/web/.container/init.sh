#!/usr/bin/env bash
set -euo pipefail

# Run from the repository/worktree root.

sanitize() {
  sed 's|/|-|g; s/[^a-zA-Z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' \
    | tr '[:upper:]' '[:lower:]'
}

WORKTREE_DIR_NAME=$(basename "$PWD")
WORKTREE_NAME=$(printf '%s' "$WORKTREE_DIR_NAME" | sanitize)

BRANCH_NAME=$(git branch --show-current | sanitize)
if [ -z "$BRANCH_NAME" ]; then
  BRANCH_NAME=$(git rev-parse --short HEAD)
fi

gitdir=$(git rev-parse --git-common-dir)
case "$gitdir" in
  /*) ;;
  *) gitdir="$PWD/$gitdir" ;;
esac
GIT_COMMON_DIR=$(cd "$gitdir" && pwd)
MAIN_REPO_DIR=$(dirname "$GIT_COMMON_DIR")
PROJECT_NAME_RAW="${PROJECT_NAME:-$(basename "$MAIN_REPO_DIR")}"
PROJECT_NAME=$(printf '%s' "$PROJECT_NAME_RAW" | sanitize)
LOCAL_WORKSPACE_FOLDER="$PWD"
NETWORK_NAME="${NETWORK_NAME:-devnet-${PROJECT_NAME}}"
APP_PORT="${APP_PORT:-3000}"
TRAEFIK_HOST="${TRAEFIK_HOST:-127.0.0.1}"
TRAEFIK_PORT="${TRAEFIK_PORT:-9876}"

mkdir -p .container

if [ ! -f ".container/Dockerfile" ]; then
  cp ".container/Dockerfile.example" ".container/Dockerfile"
  echo "[container-wt] Created .container/Dockerfile from Dockerfile.example."
fi

if [ ! -f ".container/.env.app" ]; then
  cp ".container/.env.app.example" ".container/.env.app"
  echo "[container-wt] Created .container/.env.app from .env.app.example."
fi

cat > .container/.env <<EOF
COMPOSE_FILE=docker-compose.yml
PROJECT_NAME=${PROJECT_NAME}
WORKTREE_NAME=${WORKTREE_NAME}
BRANCH_NAME=${BRANCH_NAME}
GIT_COMMON_DIR=${GIT_COMMON_DIR}
LOCAL_WORKSPACE_FOLDER=${LOCAL_WORKSPACE_FOLDER}
NETWORK_NAME=${NETWORK_NAME}
APP_PORT=${APP_PORT}
EOF

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME" >/dev/null
  echo "[container-wt] Created Docker network: ${NETWORK_NAME}"
fi

mkdir -p "${MAIN_REPO_DIR}/.container/traefik"

if [ ! -f "${MAIN_REPO_DIR}/.env" ]; then
  cat > "${MAIN_REPO_DIR}/.env" <<EOF
COMPOSE_FILE=docker-compose.infra.yml
COMPOSE_PROFILES=infra
PROJECT_NAME=${PROJECT_NAME}
NETWORK_NAME=${NETWORK_NAME}
TRAEFIK_HOST=${TRAEFIK_HOST}
TRAEFIK_PORT=${TRAEFIK_PORT}
EOF
  echo "[container-wt] Created root .env for web infra."
else
  echo "[container-wt] Root .env exists; not modified."
  echo "[container-wt] Ensure it includes docker-compose.infra.yml in COMPOSE_FILE and infra in COMPOSE_PROFILES."
fi

echo "[container-wt] Wrote .container/.env for web mode."
echo "[container-wt] Web route: http://localhost:${TRAEFIK_PORT} after running .container/route.sh"
