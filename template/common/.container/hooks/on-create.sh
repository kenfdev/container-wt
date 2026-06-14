#!/usr/bin/env bash
set -euo pipefail

# Run from anywhere inside the new worktree after creating a git worktree.
# Initializes this worktree's container environment.

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKTREE_ROOT=$(dirname "$(dirname "$SCRIPT_DIR")")
CONTAINER_DIR="${WORKTREE_ROOT}/.container"

cd "$WORKTREE_ROOT"

if [ -x "${CONTAINER_DIR}/init.sh" ]; then
  "${CONTAINER_DIR}/init.sh"
else
  echo "[container-wt] Missing executable .container/init.sh" >&2
  exit 1
fi

echo "[container-wt] on-create complete."
