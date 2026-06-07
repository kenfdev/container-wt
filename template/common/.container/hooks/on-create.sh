#!/usr/bin/env bash
set -euo pipefail

# Run from the new worktree root after creating a git worktree.
# Copies ignored files from the main worktree, then initializes this worktree's
# container environment.

gitdir=$(git rev-parse --git-common-dir)
case "$gitdir" in
  /*) ;;
  *) gitdir="$PWD/$gitdir" ;;
esac
GIT_COMMON_DIR=$(cd "$gitdir" && pwd)
MAIN_REPO_DIR=$(dirname "$GIT_COMMON_DIR")

EXCLUDE_PATTERNS=(
  '.git'
  '.git/*'
  'node_modules'
  'node_modules/*'
  '.next/*'
  '.nuxt/*'
  '__pycache__'
  '__pycache__/*'
  '.venv/*'
  'venv/*'
  '*.pyc'
  'dist/*'
  'build/*'
  '.cache/*'
  '.DS_Store'
  'Thumbs.db'
)

is_excluded() {
  local filepath="$1"
  local pattern
  for pattern in "${EXCLUDE_PATTERNS[@]}"; do
    case "$filepath" in
      $pattern) return 0 ;;
      */$pattern) return 0 ;;
    esac
  done
  return 1
}

copy_from_include_file() {
  local include_file="$1"
  local target_root="$2"
  [[ -f "$include_file" ]] || return 0

  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    (
      cd "$MAIN_REPO_DIR"
      shopt -s dotglob nullglob
      shopt -s globstar 2>/dev/null || true
      for f in $line; do
        [[ -f "$f" ]] || continue
        is_excluded "$f" && continue
        mkdir -p "${target_root}/$(dirname "$f")"
        cp "$f" "${target_root}/${f}"
        echo "[container-wt] Copied: ${f}"
      done
    )
  done < "$include_file"
}

copy_from_include_file "${MAIN_REPO_DIR}/.worktreeinclude" "$PWD"
copy_from_include_file "${MAIN_REPO_DIR}/.worktreeinclude.local" "$PWD"

if [ -x ".container/init.sh" ]; then
  .container/init.sh
else
  echo "[container-wt] Missing executable .container/init.sh" >&2
  exit 1
fi

echo "[container-wt] on-create complete."
