#!/usr/bin/env bash
set -euo pipefail

# Run from anywhere inside the worktree before removing a git worktree.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKTREE_ROOT=$(dirname "$(dirname "$SCRIPT_DIR")")
CONTAINER_DIR="${WORKTREE_ROOT}/.container"

cd "$WORKTREE_ROOT"

if [ -f "${CONTAINER_DIR}/.env" ]; then
  # shellcheck source=/dev/null
  source "${CONTAINER_DIR}/.env"
else
  echo "[container-wt] Missing .container/.env; run .container/init.sh first." >&2
  exit 1
fi

CONTAINER_NAME="app-${PROJECT_NAME}-${WORKTREE_NAME}"

if docker inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "[container-wt] Removing ${CONTAINER_NAME}..."
  docker rm -f "$CONTAINER_NAME" >/dev/null
fi

git worktree prune 2>/dev/null || true

if [ -x "${CONTAINER_DIR}/route.sh" ]; then
  echo "[container-wt] If this was the active web route, run .container/route.sh from another worktree."
fi

echo "[container-wt] on-delete complete."
