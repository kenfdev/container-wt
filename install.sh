#!/usr/bin/env bash
set -euo pipefail

REPO="kenfdev/container-wt"
BRANCH="main"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[container-wt]${NC} $*"; }
warn() { echo -e "${YELLOW}[container-wt]${NC} $*"; }
error() { echo -e "${RED}[container-wt]${NC} $*" >&2; }
success() { echo -e "${GREEN}[container-wt]${NC} $*"; }

usage() {
  cat <<EOF
Usage: install.sh [--simple|--web]

Modes:
  simple   CLI/container-shell setup. No ports or Traefik.
  web      Traefik localhost route on port 9876.
EOF
}

MODE=""
for arg in "$@"; do
  case "$arg" in
    --simple) MODE="simple" ;;
    --web) MODE="web" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      error "Unknown option: $arg"
      usage >&2
      exit 1
      ;;
  esac
done

for cmd in curl git tar; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    error "${cmd} is required but not installed."
    exit 1
  fi
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  error "Not a git repository. Run this from your project root."
  exit 1
fi

ask_tty() {
  local prompt="$1"
  local default="$2"
  local answer
  printf "${BLUE}[container-wt]${NC} %s " "$prompt" >/dev/tty
  read -r answer </dev/tty
  printf '%s' "${answer:-$default}"
}

if [ -z "$MODE" ]; then
  while true; do
    echo
    info "${BOLD}Choose setup:${NC}"
    info "  1. simple  CLI/container shell. No ports or Traefik. [default]"
    info "  2. web     Traefik localhost route for a web app."
    answer=$(ask_tty "Setup [simple]:" "simple")
    case "$answer" in
      ""|1|s|simple|S|Simple) MODE="simple"; break ;;
      2|w|web|W|Web) MODE="web"; break ;;
      *) warn "Please choose 'simple' or 'web'." ;;
    esac
  done
fi

sanitize() {
  sed 's|/|-|g; s/[^a-zA-Z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' \
    | tr '[:upper:]' '[:lower:]'
}

gitdir=$(git rev-parse --git-common-dir)
case "$gitdir" in
  /*) ;;
  *) gitdir="$PWD/$gitdir" ;;
esac
GIT_COMMON_DIR=$(cd "$gitdir" && pwd)
PROJECT_NAME_RAW="${PROJECT_NAME:-$(basename "$(dirname "$GIT_COMMON_DIR")")}"
PROJECT_NAME=$(printf '%s' "$PROJECT_NAME_RAW" | sanitize)

echo
info "${BOLD}Installing container-wt (${MODE})${NC}"
info "Source: github.com/${REPO}@${BRANCH}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading template..."
if ! curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar xz -C "$TMPDIR"; then
  error "Failed to download template. Check your network connection."
  exit 1
fi

TEMPLATE_DIR="${TMPDIR}/container-wt-${BRANCH}/template"
COMMON_DIR="${TEMPLATE_DIR}/common"
MODE_DIR="${TEMPLATE_DIR}/${MODE}"

if [ ! -d "$COMMON_DIR" ] || [ ! -d "$MODE_DIR" ]; then
  error "Unexpected archive structure. Missing common or ${MODE} template."
  exit 1
fi

MANAGED_FILES=(
  ".container/Dockerfile.example"
  ".container/.env.app.example"
  ".container/docker-compose.yml"
  ".container/init.sh"
  ".container/hooks/on-create.sh"
  ".container/hooks/on-delete.sh"
  ".worktreeinclude"
  ".dockerignore"
)

if [ "$MODE" = "web" ]; then
  MANAGED_FILES+=(
    ".container/route.sh"
    "docker-compose.infra.yml"
  )
fi

EXISTING_MANAGED=()
for f in "${MANAGED_FILES[@]}"; do
  [ -f "$f" ] && EXISTING_MANAGED+=("$f")
done

REPLACE_MANAGED="yes"
if [ ${#EXISTING_MANAGED[@]} -gt 0 ]; then
  warn "Existing managed container-wt files detected: ${EXISTING_MANAGED[*]}"
  answer=$(ask_tty "Overwrite (o), backup and replace (b), or skip existing (s)? [b]:" "b")
  case "$answer" in
    o|O) REPLACE_MANAGED="yes" ;;
    s|S) REPLACE_MANAGED="skip" ;;
    *)
      backup_dir=".container-wt-backup.$(date +%Y%m%d%H%M%S)"
      mkdir -p "$backup_dir"
      for f in "${EXISTING_MANAGED[@]}"; do
        mkdir -p "$backup_dir/$(dirname "$f")"
        cp "$f" "$backup_dir/$f"
      done
      success "Backup created: ${backup_dir}/"
      REPLACE_MANAGED="yes"
      ;;
  esac
fi

SKIPPED_FILES=()

copy_managed_file() {
  local src="$1"
  local dest="$2"
  if [ -f "$dest" ] && [ "$REPLACE_MANAGED" = "skip" ]; then
    SKIPPED_FILES+=("$dest")
    return
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
}

copy_managed_tree() {
  local base="$1"
  local file
  while IFS= read -r file; do
    rel="${file#$base/}"
    copy_managed_file "$file" "$rel"
  done < <(find "$base" -type f | sort)
}

copy_managed_tree "$COMMON_DIR"
copy_managed_tree "$MODE_DIR"

chmod +x .container/init.sh .container/hooks/on-create.sh .container/hooks/on-delete.sh
if [ "$MODE" = "web" ]; then
  chmod +x .container/route.sh
fi

USER_FILES=(
  ".container/Dockerfile"
  ".container/.env.app"
)

if [ "$MODE" = "web" ]; then
  USER_FILES+=(".env")
fi

if [ ! -f ".container/Dockerfile" ]; then
  cp ".container/Dockerfile.example" ".container/Dockerfile"
else
  SKIPPED_FILES+=(".container/Dockerfile")
fi

if [ ! -f ".container/.env.app" ]; then
  cp ".container/.env.app.example" ".container/.env.app"
else
  SKIPPED_FILES+=(".container/.env.app")
fi

if [ "$MODE" = "web" ]; then
  if [ ! -f ".env" ]; then
    cat > .env <<EOF
COMPOSE_FILE=docker-compose.infra.yml
COMPOSE_PROFILES=infra
PROJECT_NAME=${PROJECT_NAME}
NETWORK_NAME=devnet-${PROJECT_NAME}
TRAEFIK_HOST=127.0.0.1
TRAEFIK_PORT=9876
EOF
  else
    SKIPPED_FILES+=(".env")
  fi
fi

GITIGNORE_ENTRIES=(
  '# container-wt'
  '.container/.env'
  '.container/.env.app'
  '.container/Dockerfile'
  '.container/traefik/dynamic.yml'
  '.worktreeinclude.local'
)

if [ -f ".gitignore" ]; then
  if ! grep -qF "# container-wt" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    printf '%s\n' "${GITIGNORE_ENTRIES[@]}" >> .gitignore
  else
    for entry in "${GITIGNORE_ENTRIES[@]}"; do
      [[ -z "$entry" || "$entry" == \#* ]] && continue
      grep -qF "$entry" .gitignore 2>/dev/null || echo "$entry" >> .gitignore
    done
  fi
else
  printf '%s\n' "${GITIGNORE_ENTRIES[@]}" > .gitignore
fi

info "Running .container/init.sh..."
.container/init.sh

success "container-wt installed (${MODE})."
echo
if [ "$MODE" = "simple" ]; then
  info "${BOLD}Next commands:${NC}"
  info "  cd .container"
  info "  docker compose up -d --build"
  info "  docker compose exec app zsh"
else
  info "${BOLD}Next commands:${NC}"
  info "  docker compose up -d"
  info "  cd .container"
  info "  docker compose up -d --build"
  info "  cd .. && .container/route.sh"
  info "  open http://localhost:9876"
fi

skipped_text="None"
if [ ${#SKIPPED_FILES[@]} -gt 0 ]; then
  skipped_text=$(printf -- '- %s\n' "${SKIPPED_FILES[@]}")
fi

echo
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}  Paste this prompt into your coding assistant to finish setup:${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

if [ "$MODE" = "simple" ]; then
cat <<PROMPT
I've installed container-wt simple mode in this project.

Simple mode is CLI/container-shell first. It does not expose ports by default.

Files skipped or intentionally left unmodified during install:
${skipped_text}

Work through these steps one at a time. Inspect first, propose changes, and ask
before editing. Do not overwrite existing user-owned files.

1. Detect the project stack and package manager.
2. Review .container/Dockerfile and configure only the runtime/tools this project needs.
3. Review existing env examples/docs and propose .container/.env.app changes.
4. If this project needs ports even in simple mode, propose the minimal
   .container/docker-compose.yml change. Otherwise leave ports absent.
5. Run or propose the exact commands to start and enter the container:
   cd .container
   docker compose up -d --build
   docker compose exec app zsh

Summarize every file changed and why.
PROMPT
else
cat <<PROMPT
I've installed container-wt web mode in this project.

Web mode uses Traefik file-provider routing. The stable route is:
http://localhost:9876

Files skipped or intentionally left unmodified during install:
${skipped_text}

Work through these steps one at a time. Inspect first, propose changes, and ask
before editing. Do not overwrite existing user-owned files.

1. Detect the project stack and package manager.
2. Review .container/Dockerfile and configure only the runtime/tools this project needs.
3. Identify the app's internal dev-server port and update APP_PORT in .container/.env if needed.
4. Inspect existing root Compose files and root .env.
5. If root .env exists, propose a minimal change so COMPOSE_FILE includes
   docker-compose.infra.yml without removing existing compose files and without
   referencing missing files. Ensure COMPOSE_PROFILES enables infra where intended.
6. Configure shared services in docker-compose.infra.yml only if I confirm they are needed.
7. Review existing env examples/docs and propose .container/.env.app changes.
8. Verify the workflow:
   docker compose up -d
   cd .container
   docker compose up -d --build
   cd .. && .container/route.sh
   open http://localhost:9876

Summarize every file changed and why.
PROMPT
fi

echo
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
