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
#
# Or download and run:
#   curl -fsSL -o install.sh https://raw.githubusercontent.com/kenfdev/container-wt/main/install.sh
#   chmod +x install.sh
#   ./install.sh
# =============================================================================

REPO="kenfdev/container-wt"
BRANCH="main"

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

for cmd in curl git tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "${cmd} is required but not installed."
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
echo

# --- Handle existing files ---

EXISTING_FILES=()
for f in docker-compose.app.yml Dockerfile.base Dockerfile.app init.sh dev; do
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
        cp "$f" "$backup_dir/"
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

# --- Install core files ---

info "Installing Dockerfiles..."
cp "$TEMPLATE_DIR/Dockerfile.base" .
cp "$TEMPLATE_DIR/Dockerfile.app" .

info "Installing docker-compose files..."
cp "$TEMPLATE_DIR/docker-compose.yml" .
cp "$TEMPLATE_DIR/docker-compose.app.yml" .
cp "$TEMPLATE_DIR/docker-compose.local.example.yml" .

info "Installing init.sh and dev wrapper..."
cp "$TEMPLATE_DIR/init.sh" .
cp "$TEMPLATE_DIR/dev" .
chmod +x init.sh dev

info "Installing .env.app.template..."
cp "$TEMPLATE_DIR/.env.app.template" .

info "Installing .worktreeinclude..."
cp "$TEMPLATE_DIR/.worktreeinclude" .

# Install example personal Dockerfile
info "Installing .docker/dev/example/..."
mkdir -p .docker/dev/example
cp "$TEMPLATE_DIR/.docker/dev/example/Dockerfile" .docker/dev/example/

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
  '.env'
  '.env.app'
  'docker-compose.local.yml'
  ''
  '# Personal Dockerfiles (gitignored except example)'
  '.docker/dev/*/Dockerfile'
  '!.docker/dev/example/Dockerfile'
  ''
  '# Personal worktreeinclude (not tracked)'
  '.worktreeinclude.local'
)

if [ -f ".gitignore" ]; then
  # Add entries that don't already exist
  for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if [ -z "$entry" ]; then
      continue
    fi
    if [[ "$entry" == \#* ]]; then
      continue
    fi
    if ! grep -qF "$entry" .gitignore 2>/dev/null; then
      echo "$entry" >> .gitignore
    fi
  done
else
  printf '%s\n' "${GITIGNORE_ENTRIES[@]}" > .gitignore
fi

success "Core template files installed."

# --- Done ---

echo
success "container-wt installed successfully!"
echo
info "${BOLD}Next steps:${NC}"
info "  1. Edit Dockerfile.base                  -- add team-wide system deps"
info "  2. Edit Dockerfile.app                   -- add project-specific deps"
info "  3. Edit docker-compose.yml               -- add infra (Postgres, Redis, etc.)"
info "  4. Edit .env.app.template                -- add per-worktree env vars"
info "  5. ./dev infra                           -- start shared infrastructure"
info "  6. ./dev up                              -- start the app container"
info "  7. ./dev exec                            -- open a shell in the container"
echo
info "For personal Dockerfile customization:"
info "  1. Copy .docker/dev/example/Dockerfile to .docker/dev/<your-name>/Dockerfile"
info "  2. Copy docker-compose.local.example.yml to docker-compose.local.yml"
info "  3. Point it to your personal Dockerfile"
echo
info "If you are using git-wt, configure worktree hooks (recommended):"
info "  git config wt.basedir .git/wt"
info "  git config --add wt.hook \".worktree/hooks/on-create.sh\""
info "  git config --add wt.deletehook \".worktree/hooks/on-delete.sh\""
echo
