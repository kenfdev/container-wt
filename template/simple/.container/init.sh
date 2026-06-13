#!/usr/bin/env bash
set -euo pipefail

# Run from anywhere inside the repository/worktree.

sanitize() {
  sed 's|/|-|g; s/[^a-zA-Z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' \
    | tr '[:upper:]' '[:lower:]'
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKTREE_ROOT=$(dirname "$SCRIPT_DIR")
CONTAINER_DIR="${WORKTREE_ROOT}/.container"

cd "$WORKTREE_ROOT"

WORKTREE_DIR_NAME=$(basename "$WORKTREE_ROOT")
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
PROJECT_NAME_RAW="${PROJECT_NAME:-$(basename "$(dirname "$GIT_COMMON_DIR")")}"
PROJECT_NAME=$(printf '%s' "$PROJECT_NAME_RAW" | sanitize)
LOCAL_WORKSPACE_FOLDER="$WORKTREE_ROOT"
APP_IMAGE_NAME="${APP_IMAGE_NAME:-container-wt-${PROJECT_NAME}-app}"

mkdir -p "$CONTAINER_DIR"

if [ ! -f "${CONTAINER_DIR}/Dockerfile" ]; then
  cp "${CONTAINER_DIR}/Dockerfile.example" "${CONTAINER_DIR}/Dockerfile"
  echo "[container-wt] Created .container/Dockerfile from Dockerfile.example."
fi

if [ ! -f "${CONTAINER_DIR}/.env.app" ]; then
  cp "${CONTAINER_DIR}/.env.app.example" "${CONTAINER_DIR}/.env.app"
  echo "[container-wt] Created .container/.env.app from .env.app.example."
fi

cat > "${CONTAINER_DIR}/.env" <<EOF
COMPOSE_FILE=docker-compose.yml
PROJECT_NAME=${PROJECT_NAME}
WORKTREE_NAME=${WORKTREE_NAME}
BRANCH_NAME=${BRANCH_NAME}
GIT_COMMON_DIR=${GIT_COMMON_DIR}
LOCAL_WORKSPACE_FOLDER=${LOCAL_WORKSPACE_FOLDER}
APP_IMAGE_NAME=${APP_IMAGE_NAME}
EOF

echo "[container-wt] Wrote .container/.env for simple mode."
