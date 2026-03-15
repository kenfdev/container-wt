# container-wt

Seamless Docker + git worktree workflows. Run multiple feature branches simultaneously, each in its own isolated container with its own database, routed via Traefik subdomains. No devcontainer CLI or VS Code required.

## What You Get

- **Git works inside containers** -- worktree `.git` file resolution is fixed automatically via volume mount (no file mutation).
- **No port conflicts** -- Traefik routes by subdomain, so every worktree container can listen on the same internal port.
- **Per-worktree database** -- each worktree gets its own database, created automatically on startup.
- **Per-worktree env vars** -- `.env.app.template` is expanded per worktree with `${WORKTREE_NAME}`, `${BRANCH_NAME}`, `${PROJECT_NAME}`, etc.
- **Personal Dockerfiles** -- each developer can customize their container image without touching shared files.
- **Simple `./dev` wrapper** -- `./dev up`, `./dev exec`, `./dev down` for everyday use.

## Install

Run this from your project's root directory:

```bash
curl -fsSL https://raw.githubusercontent.com/kenfdev/container-wt/main/install.sh | bash
```

The installer will:
- Download the template files from GitHub
- Set up Dockerfiles, compose files, init script, and `dev` wrapper
- Prompt to backup if existing files are detected

## Directory Structure

```
myapp/                              # <-- you are here (main worktree)
  .git/                             # git database (directory)
  docker-compose.yml                # shared infra (Traefik, Postgres, Redis)
  docker-compose.app.yml            # per-worktree app service
  docker-compose.local.yml          # personal overrides (gitignored)
  Dockerfile.base                   # team-shared base image
  Dockerfile.app                    # default app image (FROM devbase)
  .docker/dev/example/Dockerfile    # example personal Dockerfile
  init.sh                           # host-side: generates .env, .env.app
  dev                               # wrapper script (./dev up, exec, down)
  .env                              # generated (gitignored)
  .env.app                          # generated (gitignored)
  .env.app.template                 # per-worktree env var template (tracked)
  .worktreeinclude                  # glob patterns for worktree file copy
  .worktree/hooks/
    on-create.sh                    # worktree creation hook
    on-delete.sh                    # worktree deletion hook
```

## Quick Start

### 1. Start Infrastructure

```bash
cd myapp
./dev infra
# Traefik dashboard: http://traefik.myapp.localhost
```

### 2. Start the App Container

```bash
./dev up
# App: http://main.myapp.localhost
```

### 3. Enter the Container

```bash
./dev exec
```

### 4. Create a Feature Worktree

From the host terminal:

```bash
git worktree add ../myapp-feature-x -b feature-x
cd ../myapp-feature-x
.worktree/hooks/on-create.sh   # copies gitignored files
./dev up
# App: http://feature-x.myapp.localhost
```

With [git-wt](https://github.com/k1LoW/git-wt):

```bash
git wt feature-x
cd ../myapp-feature-x
./dev up
```

## URL Pattern

```
http://{BRANCH_NAME}.{PROJECT_NAME}.localhost
```

| What | URL |
|---|---|
| Main worktree (branch `main`) | `http://main.myapp.localhost` |
| Feature worktree (`feature-x`) | `http://feature-x.myapp.localhost` |
| Traefik dashboard | `http://traefik.myapp.localhost` |

## `./dev` Commands

| Command | What It Does |
|---|---|
| `./dev up` | Run `init.sh`, create Docker network, start app container |
| `./dev down` | Stop the app container |
| `./dev exec` | Open a shell in the running app container |
| `./dev build` | Rebuild the app image |
| `./dev infra` | Start shared infrastructure (Traefik, DB, etc.) |
| `./dev logs` | Tail app container logs |

## Dockerfile Layering

```
Dockerfile.base          Team-shared base (ubuntu + git, curl, zsh)
      |
Dockerfile.app           Default app (project-specific deps)
      |
.docker/dev/X/Dockerfile Personal (neovim, claude, etc.)
```

All Dockerfiles use `FROM devbase`. The `devbase` named context is provided by `additional_contexts: devbase: service:base` in the compose file, ensuring the base image is always built first.

### Personal Dockerfile Setup

1. Copy `.docker/dev/example/Dockerfile` to `.docker/dev/<your-name>/Dockerfile`
2. Copy `docker-compose.local.example.yml` to `docker-compose.local.yml`
3. Update `docker-compose.local.yml` to point to your Dockerfile

## Customization

### Add Infrastructure Services

Edit `docker-compose.yml` to add services (Postgres, Redis, etc.):

```yaml
  postgres:
    image: postgres:16
    container_name: "postgres-${PROJECT_NAME:-myapp}"
    environment:
      POSTGRES_PASSWORD: dev
      POSTGRES_USER: dev
    ports:
      - "${POSTGRES_HOST_PORT:-15432}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      - devnet
    restart: unless-stopped
```

### Add Environment Variables

Edit `.env.app.template` (tracked in git):

```bash
DATABASE_URL=postgres://dev:dev@postgres-${PROJECT_NAME}:5432/${PROJECT_NAME}_${WORKTREE_NAME}
REDIS_URL=redis://redis-${PROJECT_NAME}:6379/0
APP_NAME=${PROJECT_NAME}-${WORKTREE_NAME}
```

### Change the App Port

Update the Traefik label in `docker-compose.app.yml`:

```yaml
- "traefik.http.services.${PROJECT_NAME}-${WORKTREE_NAME}.loadbalancer.server.port=4000"
```

### Change the Traefik Port

```bash
export TRAEFIK_PORT=8000
./dev infra
```

## Prerequisites

| Requirement | Notes |
|---|---|
| **Docker Desktop** (macOS) or **Docker Engine** (Linux) | Must be running. |
| **git** | Any recent version with worktree support. |
| **envsubst** | Pre-installed on most Linux. On macOS: `brew install gettext`. |

## How the Git Fix Works

A git worktree's `.git` is a **file** containing an absolute host path. When mounted into a container, this path doesn't exist. The template mounts the git common directory at the same absolute host path inside the container:

```
Host: /Users/you/myapp/.git/  →  Container: /Users/you/myapp/.git/  (same path)
```

The `.git` file is **never modified**. No symlink or post-start script needed.

## Platform Notes

### macOS

`*.localhost` resolves to `127.0.0.1` by default. No configuration needed.

### Linux

`*.localhost` wildcard resolution may not work. Use `/etc/hosts` or `dnsmasq`:

```
# /etc/hosts
127.0.0.1 main.myapp.localhost feature-x.myapp.localhost traefik.myapp.localhost

# Or dnsmasq for wildcard
address=/localhost/127.0.0.1
```

## Limitations

- **Main worktree must start infra first.** Infrastructure services only run from the main worktree.
- **Name collisions.** Branch names like `feature/login` and `feature-login` both sanitize to `feature-login`. Use distinct branch names.
- **GitHub Codespaces not supported.** Different constraints (no Traefik, no sibling worktrees).
