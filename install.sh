#!/bin/bash
set -euo pipefail

# =============================================================================
# container-wt installer
#
# Installs the container-wt template into the current project.
# Downloads template files from GitHub and sets up the plain Docker workflow.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kenfdev/container-wt/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/kenfdev/container-wt/main/install.sh | bash -s -- --slim
#
# Or download and run:
#   curl -fsSL -o install.sh https://raw.githubusercontent.com/kenfdev/container-wt/main/install.sh
#   chmod +x install.sh
#   ./install.sh [--slim]
#
# Options:
#   --slim   Install without shared infrastructure (Traefik, Docker network,
#            root docker-compose.yml). The app exposes ports directly.
# =============================================================================

REPO="kenfdev/container-wt"
BRANCH="main"

# --- Parse flags ---

SLIM=false
for arg in "$@"; do
  case "$arg" in
    --slim) SLIM=true ;;
  esac
done

# --- Colors ---

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[container-wt]${NC} $*"; }
warn()    { echo -e "${YELLOW}[container-wt]${NC} $*"; }
error()   { echo -e "${RED}[container-wt]${NC} $*" >&2; }
success() { echo -e "${GREEN}[container-wt]${NC} $*"; }

# Prompt helper that reads from /dev/tty (works with curl | bash).
ask() {
  local prompt="$1"
  local default="$2"
  local answer
  echo -en "${BLUE}[container-wt]${NC} ${prompt} " > /dev/tty
  read -r answer < /dev/tty
  echo "${answer:-$default}"
}

# --- Prerequisites ---

for cmd in curl git tar envsubst; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "${cmd} is required but not installed."
    if [ "$cmd" = "envsubst" ]; then
      error "On macOS: brew install gettext"
    fi
    exit 1
  fi
done

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  error "Not a git repository. Run this from inside your project."
  exit 1
fi

echo
info "${BOLD}Installing container-wt template${NC}"
info "Source: github.com/${REPO}@${BRANCH}"
if [ "$SLIM" = true ]; then
  info "Mode: ${BOLD}slim${NC} (no shared infrastructure)"
fi
echo

# --- Handle existing files ---

EXISTING_FILES=()
for f in .worktree/docker-compose.yml .worktree/Dockerfile.base .worktree/Dockerfile.app .worktree/init.sh; do
  [ -f "$f" ] && EXISTING_FILES+=("$f")
done

if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
  warn "Existing container-wt files detected: ${EXISTING_FILES[*]}"
  answer=$(ask "Overwrite (o) or backup and replace (b)? [b]:" "b")
  case "$answer" in
    o|O)
      info "Will overwrite existing files..."
      ;;
    *)
      backup_dir=".container-wt-backup.$(date +%Y%m%d%H%M%S)"
      mkdir -p "$backup_dir"
      for f in "${EXISTING_FILES[@]}"; do
        mkdir -p "$backup_dir/$(dirname "$f")"
        cp "$f" "$backup_dir/$f"
      done
      success "Backup created: ${backup_dir}/"
      ;;
  esac
  echo
fi

# --- Download template ---

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading template from GitHub..."
if ! curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar xz -C "$TMPDIR"; then
  error "Failed to download template. Check your network connection."
  exit 1
fi
TEMPLATE_DIR="${TMPDIR}/container-wt-${BRANCH}/template"

if [ ! -d "$TEMPLATE_DIR" ]; then
  error "Unexpected archive structure. Expected directory: container-wt-${BRANCH}/template"
  exit 1
fi

# --- Install .worktree files ---

info "Installing .worktree/..."
mkdir -p .worktree
cp "$TEMPLATE_DIR/.worktree/Dockerfile.base" .worktree/
cp "$TEMPLATE_DIR/.worktree/Dockerfile.app" .worktree/
cp "$TEMPLATE_DIR/.worktree/Dockerfile.local.example" .worktree/
if [ "$SLIM" = true ]; then
  cp "$TEMPLATE_DIR/.worktree/docker-compose.slim.yml" .worktree/docker-compose.yml
else
  cp "$TEMPLATE_DIR/.worktree/docker-compose.yml" .worktree/
fi
cp "$TEMPLATE_DIR/.worktree/docker-compose.local.example.yml" .worktree/
cp "$TEMPLATE_DIR/.worktree/init.sh" .worktree/
chmod +x .worktree/init.sh

info "Installing .env.app.template..."
cp "$TEMPLATE_DIR/.worktree/.env.app.template" .worktree/

# --- Install root-level files ---

if [ "$SLIM" = true ]; then
  info "Skipping root docker-compose.yml (slim mode)."
else
  info "Installing docker-compose.yml (infra)..."
  cp "$TEMPLATE_DIR/docker-compose.yml" .
fi

info "Installing .worktreeinclude..."
cp "$TEMPLATE_DIR/.worktreeinclude" .

info "Installing .dockerignore..."
cp "$TEMPLATE_DIR/.dockerignore" .

# Install worktree hooks
info "Installing .worktree/hooks/..."
mkdir -p .worktree/hooks
cp "$TEMPLATE_DIR/.worktree/hooks/on-create.sh" .worktree/hooks/
cp "$TEMPLATE_DIR/.worktree/hooks/on-delete.sh" .worktree/hooks/
chmod +x .worktree/hooks/on-create.sh
chmod +x .worktree/hooks/on-delete.sh

# --- Update .gitignore ---

GITIGNORE_ENTRIES=(
  '# container-wt generated files'
)
if [ "$SLIM" = false ]; then
  GITIGNORE_ENTRIES+=('.env')
fi
GITIGNORE_ENTRIES+=(
  '.worktree/.env'
  '.worktree/.env.app'
  '.worktree/docker-compose.local.yml'
  ''
  '# Personal Dockerfile (gitignored)'
  '.worktree/Dockerfile.local'
  ''
  '# Personal worktreeinclude (not tracked)'
  '.worktreeinclude.local'
)

if [ -f ".gitignore" ]; then
  # Check if container-wt section already exists
  if ! grep -qF "# container-wt generated files" .gitignore 2>/dev/null; then
    # Add a blank line separator, then all entries as a block
    echo "" >> .gitignore
    printf '%s\n' "${GITIGNORE_ENTRIES[@]}" >> .gitignore
  else
    # Section exists — add any missing non-comment, non-empty patterns
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
      [[ -z "$entry" || "$entry" == \#* ]] && continue
      if ! grep -qF "$entry" .gitignore 2>/dev/null; then
        echo "$entry" >> .gitignore
      fi
    done
  fi
else
  printf '%s\n' "${GITIGNORE_ENTRIES[@]}" > .gitignore
fi

success "Template files installed."

# --- Run init.sh to generate .env files ---

info "Running init.sh to generate .env files..."
.worktree/init.sh

# --- Done ---

echo
success "container-wt installed successfully!"
echo
info "${BOLD}Next steps:${NC}"
info "  1. Edit .worktree/Dockerfile.base       -- add team-wide system deps"
info "  2. Edit .worktree/Dockerfile.app         -- add project-specific deps"
if [ "$SLIM" = true ]; then
  info "  3. Edit .worktree/.env.app.template            -- add per-worktree env vars"
  info "  4. Start the app container:"
  info "       cd .worktree && docker compose up -d --build"
  info "  5. Enter the container:"
  info "       cd .worktree && docker compose exec app zsh"
else
  info "  3. Edit docker-compose.yml                   -- add infra (Postgres, Redis, etc.)"
  info "  4. Edit .worktree/.env.app.template            -- add per-worktree env vars"
  info "  5. Start shared infrastructure:"
  info "       docker compose up -d"
  info "  6. Start the app container:"
  info "       cd .worktree && docker compose up -d --build"
  info "  7. Enter the container:"
  info "       cd .worktree && docker compose exec app zsh"
fi
echo
info "For personal Dockerfile customization:"
info "  1. Copy .worktree/Dockerfile.local.example to .worktree/Dockerfile.local"
info "  2. Copy .worktree/docker-compose.local.example.yml to .worktree/docker-compose.local.yml"
info "  3. Uncomment the build override in docker-compose.local.yml"
info "  4. Add to .worktreeinclude.local: .worktree/Dockerfile.local"
echo
info "If you are using git-wt, configure worktree hooks (recommended):"
info "  git config wt.basedir .git/wt"
info "  git config --add wt.hook \".worktree/hooks/on-create.sh\""
info "  git config --add wt.deletehook \".worktree/hooks/on-delete.sh\""
echo
