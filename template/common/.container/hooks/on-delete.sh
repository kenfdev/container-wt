#!/usr/bin/env bash
set -euo pipefail

# Run from the worktree root before removing a git worktree.

if [ -f ".container/.env" ]; then
  # shellcheck source=/dev/null
  source ".container/.env"
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

if [ -x ".container/route.sh" ]; then
  echo "[container-wt] If this was the active web route, run .container/route.sh from another worktree."
fi

echo "[container-wt] on-delete complete."
