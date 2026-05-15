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
for f in .worktree/docker-compose.yml .worktree/Dockerfile.base .worktree/init.sh; do
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

# --- Optionally set up local environment files ---

SETUP_LOCAL=false
echo
answer=$(ask "Set up local environment files? (Dockerfile.local + docker-compose.local.yml) [y/N]:" "n")
if [[ "$answer" =~ ^[Yy]$ ]]; then
  SETUP_LOCAL=true

  # Dockerfile.local
  if [ -f ".worktree/Dockerfile.local" ]; then
    ow=$(ask ".worktree/Dockerfile.local already exists. Overwrite? [y/N]:" "n")
    if [[ "$ow" =~ ^[Yy]$ ]]; then
      cp ".worktree/Dockerfile.local.example" ".worktree/Dockerfile.local"
      success "Copied Dockerfile.local.example -> Dockerfile.local"
    else
      warn "Skipped .worktree/Dockerfile.local (already exists)"
    fi
  else
    cp ".worktree/Dockerfile.local.example" ".worktree/Dockerfile.local"
    success "Created .worktree/Dockerfile.local"
  fi

  # docker-compose.local.yml
  if [ -f ".worktree/docker-compose.local.yml" ]; then
    ow=$(ask ".worktree/docker-compose.local.yml already exists. Overwrite? [y/N]:" "n")
    if [[ "$ow" =~ ^[Yy]$ ]]; then
      cp ".worktree/docker-compose.local.example.yml" ".worktree/docker-compose.local.yml"
      success "Copied docker-compose.local.example.yml -> docker-compose.local.yml"
    else
      warn "Skipped .worktree/docker-compose.local.yml (already exists)"
    fi
  else
    cp ".worktree/docker-compose.local.example.yml" ".worktree/docker-compose.local.yml"
    success "Created .worktree/docker-compose.local.yml"
  fi
fi

# --- Run init.sh to generate .env files ---

info "Running init.sh to generate .env files..."
.worktree/init.sh

# --- Done ---

echo
success "container-wt installed successfully!"
echo
info "${BOLD}Next steps:${NC}"
info "  1. Edit .worktree/Dockerfile.base       -- add team + project deps (runtimes, tools, libs)"
if [ "$SLIM" = true ]; then
  info "  2. Edit .worktree/.env.app.template            -- add per-worktree env vars"
  info "  3. Start the app container:"
  info "       cd .worktree && docker compose up -d --build"
  info "  4. Enter the container:"
  info "       cd .worktree && docker compose exec app zsh"
else
  info "  2. Edit docker-compose.yml                   -- add infra (Postgres, Redis, etc.)"
  info "  3. Edit .worktree/.env.app.template            -- add per-worktree env vars"
  info "  4. Start shared infrastructure:"
  info "       docker compose up -d"
  info "  5. Start the app container:"
  info "       cd .worktree && docker compose up -d --build"
  info "  6. Enter the container:"
  info "       cd .worktree && docker compose exec app zsh"
fi
echo
if [ "$SETUP_LOCAL" = true ]; then
  info "For personal Dockerfile customization:"
  info "  1. Edit .worktree/Dockerfile.local        -- add your personal tools"
  info "  2. Add to .worktreeinclude.local: .worktree/Dockerfile.local"
else
  info "For personal Dockerfile customization:"
  info "  1. Copy .worktree/Dockerfile.local.example to .worktree/Dockerfile.local"
  info "  2. Copy .worktree/docker-compose.local.example.yml to .worktree/docker-compose.local.yml"
  info "  3. Edit .worktree/Dockerfile.local        -- add your personal tools"
  info "  4. Add to .worktreeinclude.local: .worktree/Dockerfile.local"
fi
echo
info "If you are using worktrunk, configure worktree hooks (recommended):"
info "  wt config create --project"
info "  # Then add to .config/wt.toml:"
info "  pre-start = \".worktree/hooks/on-create.sh\""
info "  pre-remove = \".worktree/hooks/on-delete.sh\""
echo

# --- AI setup prompt ---

echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Paste this prompt into your AI assistant to finish the project setup:${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
if [ "$SLIM" = true ]; then
cat <<'PROMPT'
I've just set up a Docker-based development environment in this project.
Help me finish configuring it for this specific project.

Work through the following steps one at a time, asking me to confirm or provide
input before making any file changes. Never do multiple steps at once.

Step 1 — Tech stack detection
Read the project files (package.json, go.mod, Pipfile, Gemfile, Cargo.toml,
pom.xml, etc.) and tell me what language runtime(s) and package manager(s) you
detected. Ask me to confirm or correct before proceeding.

Step 2 — App port
Based on the detected stack and any config files or README, what port does the
dev server run on? Tell me your best guess and ask me to confirm or override.
You will update the port mapping in .worktree/docker-compose.yml to this port.

Step 3 — Runtime environment variables
Based on any .env.example or README in the project, show me the environment
variables you plan to add to .worktree/.env.app.template and ask me to confirm
or edit them before writing.

Step 4 — Personal Dockerfile customization
Ask me to paste the contents of any previous personal Dockerfile I've used on
other projects (editors, AI CLIs, shell configs, personal tools, etc.).
If I provide one, adapt it for the base image used in this project's
Dockerfile.base and write it to .worktree/Dockerfile.local.
If I have nothing to paste, tell me that .worktree/Dockerfile.local is where I
can add personal tooling on top of the team image, and give me two or three
example snippets relevant to the detected stack as a starting point.

After all steps are confirmed and applied, summarize every file changed and
what was done.
PROMPT
else
cat <<'PROMPT'
I've just set up a Docker-based development environment in this project.
Help me finish configuring it for this specific project.

Work through the following steps one at a time, asking me to confirm or provide
input before making any file changes. Never do multiple steps at once.

Step 1 — Tech stack detection
Read the project files (package.json, go.mod, Pipfile, Gemfile, Cargo.toml,
pom.xml, etc.) and tell me what language runtime(s) and package manager(s) you
detected. Ask me to confirm or correct before proceeding.

Step 2 — App port
Based on the detected stack and any config files or README, what port does the
dev server run on? Tell me your best guess and ask me to confirm or override.
You will update the reverse-proxy routing label in .worktree/docker-compose.yml
to this port.

Step 3 — Infrastructure services
Ask me which backing services this project needs (e.g. Postgres, Redis, MySQL,
S3-compatible storage). Uncomment and configure the relevant services in
docker-compose.yml only for what I confirm.

Step 4 — Runtime environment variables
Based on the services confirmed in Step 3 and any .env.example or README in the
project, show me the environment variables you plan to add to
.worktree/.env.app.template and ask me to confirm or edit them before writing.

Step 5 — Personal Dockerfile customization
Ask me to paste the contents of any previous personal Dockerfile I've used on
other projects (editors, AI CLIs, shell configs, personal tools, etc.).
If I provide one, adapt it for the base image used in this project's
Dockerfile.base and write it to .worktree/Dockerfile.local.
If I have nothing to paste, tell me that .worktree/Dockerfile.local is where I
can add personal tooling on top of the team image, and give me two or three
example snippets relevant to the detected stack as a starting point.

After all steps are confirmed and applied, summarize every file changed and
what was done.
PROMPT
fi
echo
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
