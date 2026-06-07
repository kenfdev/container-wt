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
PROJECT_NAME_RAW="${PROJECT_NAME:-$(basename "$(dirname "$GIT_COMMON_DIR")")}"
PROJECT_NAME=$(printf '%s' "$PROJECT_NAME_RAW" | sanitize)
LOCAL_WORKSPACE_FOLDER="$PWD"

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
EOF

echo "[container-wt] Wrote .container/.env for simple mode."
