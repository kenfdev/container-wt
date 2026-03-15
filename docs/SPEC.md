# container-wt

A thin, opinionated template for seamless Docker + git worktree workflows. No devcontainer CLI or VS Code required. Worktree management is delegated to external tools (e.g., [git-wt](https://github.com/k1LoW/git-wt), [wtp](https://github.com/satococoa/wtp), or raw `git worktree`). This template focuses only on what those tools can't do: making containers work correctly with worktrees.

## Problem

Working with containers and git worktrees simultaneously is painful:

1. **Git context breaks inside containers.** A git worktree's `.git` is a file (not a directory) containing an absolute host path (e.g. `gitdir: /Users/you/repo/.git/worktrees/feature-x`). When the worktree is mounted into a container at a different path (e.g. `/workspaces/repo-feature-x`), this host path doesn't resolve. All git operations (`log`, `blame`, `status`) fail inside the container. Note: this problem is specific to worktrees — regular repos have a `.git` directory that gets mounted alongside the project and works fine.

2. **Port conflicts.** Each container maps ports to the host (e.g. `3000:3000`). Running multiple worktree containers simultaneously causes port binding conflicts.

3. **No shared infrastructure.** Each container typically spins up its own database, cache, etc. There's no built-in way to share these across worktrees or isolate data per worktree within a shared service.

4. **Gitignored files don't propagate.** When creating a worktree, git only checks out tracked files. Gitignored files (`.env`, `docker-compose.local.yml`, IDE configs) must be manually copied.

## Solution Overview

**container-wt** is a template-only approach that solves these problems using plain Docker Compose, Dockerfiles, and shell scripts:

- **Git fix:** Mount the git common directory at the same absolute host path inside the container so the `.git` file's host path references resolve directly. No symlink or file mutation needed.
- **No port conflicts:** A per-project Traefik reverse proxy routes by subdomain (`feature-x.myapp.localhost`, using the branch name). No host port mapping needed per worktree. Traefik port is configurable.
- **Shared infrastructure:** Infrastructure services (database, cache, proxy) run from a standalone `docker-compose.yml` at the project root — started with `docker compose -f docker-compose.yml up -d` on the host. Per-worktree app containers join a shared Docker network.
- **Gitignored file propagation:** `.worktreeinclude` + `.worktreeinclude.local` define glob patterns for files to copy to new worktrees. Copying is handled by worktree tool hooks (e.g., `git-wt`'s `wt.hook`).
- **Per-worktree env vars:** A `.worktree/.env.app.template` (tracked in git) with `${VARIABLE}` placeholders is expanded by `init.sh` into `.worktree/.env.app` (gitignored) per worktree.
- **Dockerfile layering:** `Dockerfile.base` (team-shared) + `Dockerfile.app` (project-specific) + personal `.worktree/personal/<name>/Dockerfile` for individual customization. All use `FROM devbase` with `additional_contexts` ensuring the base is always built first.
- **Lifecycle hooks:** `.worktree/hooks/on-create.sh` and `.worktree/hooks/on-delete.sh` provide extension points for worktree tool hooks (file copying, container cleanup, DB teardown).

## Target User

Solo developer on macOS or Linux managing multiple feature branches simultaneously, including parallel AI coding agents (one agent per worktree). The primary workflows are:

1. **Parallel development:** Work on multiple features at the same time, each in its own container (human or AI agent).
2. **PR review:** Quickly spin up a colleague's branch, test it in a full environment, tear it down.

## Architecture

```
                          Host Machine
  ┌──────────────────────────────────────────────────┐
  │                                                  │
  │  myapp/  (main worktree)                         │
  │    .git/                                         │
  │    .worktree/                                │
  │      docker-compose.yml   (app — per worktree)   │
  │      Dockerfile.base / Dockerfile.app            │
  │      init.sh                                     │
  │    docker-compose.yml     (infra — shared)       │
  │    src/                                          │
  │                                                  │
  │  feature-x/  (worktree)                            │
  │    .git  (file → myapp/.git/worktrees/feature-x) │
  │    .worktree/  (tracked in git)              │
  │    src/                                          │
  │                                                  │
  └──────────────────────────────────────────────────┘

  Host: docker compose -f docker-compose.yml up -d (from myapp/)
  ┌──────────────────────────────────────────────────┐
  │  ┌─────────┐  ┌──────────┐  ┌────────┐          │
  │  │ Traefik │  │ Postgres │  │ Redis  │  ...      │
  │  │ :80     │  │ :5432    │  │ :6379  │           │
  │  └────┬────┘  └──────────┘  └────────┘          │
  │       │           Shared Infrastructure          │
  │       │     (started independently on host)      │
  └───────┼──────────────────────────────────────────┘
          │
          │  Docker Network: devnet-myapp
  ┌───────┼──────────────────────────────────────────┐
  │  ┌────┴──────────────┬──────────────────┐       │
  │  │                   │                  │        │
  │  ▼                   ▼                  ▼        │
  │ ┌──────────┐  ┌──────────────┐  ┌──────────┐   │
  │ │app-myapp-│  │app-myapp-    │  │app-myapp-│   │
  │ │  myapp   │  │  feature-x   │  │  pr-123  │   │
  │ │ :3000    │  │ :3000        │  │ :3000    │   │
  │ └──────────┘  └──────────────┘  └──────────┘   │
  │  Per-worktree app containers                     │
  │  (no host port mapping — Traefik routes traffic) │
  └──────────────────────────────────────────────────┘

  Browser (routes by branch name):
    main.myapp.localhost            → app-myapp-myapp:3000
    feature-x.myapp.localhost       → app-myapp-feature-x:3000
    pr-123.myapp.localhost          → app-myapp-pr-123:3000

  Traefik Dashboard:
    traefik.myapp.localhost         → Traefik dashboard (debug routing)
```

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Git fix | Same-path volume mount (no file mutation) | Mounts the git common directory at the same absolute host path inside the container. The `.git` file's host path references resolve directly. No symlink or post-start script needed. |
| Directory layout | Sibling directories | Most common git worktree pattern. Main worktree is a natural home for shared infra. |
| Container runtime | Plain Docker Compose + Dockerfile | No devcontainer CLI, VS Code, or features required. Works from any terminal. |
| File organization | `.worktree/` directory | All container-wt files (Dockerfiles, app compose, init.sh, personal Dockerfiles, env template) live inside `.worktree/` to avoid polluting the project root. Only `docker-compose.yml` (infra) remains at root. |
| Dockerfile layering | `Dockerfile.base` + `Dockerfile.app` + personal | Team-shared base, project-specific app, personal customization. All use `FROM devbase` with `additional_contexts` for build ordering. |
| Worktree management | External tools (git-wt, wtp, raw git worktree) | Template does NOT wrap `git worktree`. Users choose their preferred tool. Template provides hook scripts that any tool can call. |
| Port conflict solution | Traefik with subdomain routing | Single entry point, configurable port (default 80). Auto-discovers containers via Docker labels. Zero-config per worktree. |
| Routing pattern | Always `{branch}.{project}.localhost` | Consistent pattern using the git branch name. Main worktree gets `main.myapp.localhost`. |
| Container naming | Always `app-{project}-{worktree}` | Consistent pattern, no special-casing. |
| Docker Compose UX | `COMPOSE_FILE` env var in `.env` | `init.sh` writes `COMPOSE_FILE=.worktree/docker-compose.yml:.worktree/docker-compose.local.yml` to `.env`. Users run `docker compose up` from project root without `-f` flags. |
| Network isolation | Per-project Docker network (`devnet-{project}`) | Prevents container name collisions and unintended cross-project access. |
| Compose project naming | Infra: `{PROJECT_NAME}-infra`, App: `{PROJECT_NAME}-{BRANCH_NAME}` | Each compose file sets its own project name via the top-level `name:` attribute. `COMPOSE_PROJECT_NAME` is intentionally NOT set in `.env` to prevent it from leaking across compose files. |
| Infra lifecycle | Standalone `docker-compose.yml` at project root | Infrastructure runs independently on the host via `docker compose -f docker-compose.yml up -d`. No devcontainer required. |
| Per-worktree env vars | `.worktree/.env.app.template` expanded by `init.sh` | Tracked template with `${VARIABLE}` placeholders. `init.sh` renders it into `.worktree/.env.app` (gitignored) per worktree via `envsubst`. |
| Personal Dockerfiles | `.worktree/personal/<name>/Dockerfile` with `docker-compose.local.yml` override | Each developer can customize their image without touching shared files. Base image inheritance guaranteed via `additional_contexts`. |
| .env location | Project root | Docker Compose auto-reads `.env` from the directory where it's invoked. Contains `COMPOSE_FILE` and all template variables. Does NOT contain `COMPOSE_PROJECT_NAME` (set via `name:` in each compose file instead). |
| Worktree hooks | `.worktree/hooks/on-create.sh` and `on-delete.sh` | Prescribed hook scripts at a well-known location. Users wire them into their worktree tool of choice. `on-create.sh` also runs `init.sh` to generate .env files automatically. |
| Worktreeinclude | `.worktreeinclude` + `.worktreeinclude.local` at repo root | Glob patterns for gitignored files to copy from main worktree to new worktrees. |
| Local compose overrides | `.worktree/docker-compose.local.yml` (gitignored) | Personal Docker Compose overrides. Example template tracked as `.worktree/docker-compose.local.example.yml`. |
| Platform | macOS + Linux | Template works on both Docker Desktop (macOS) and native Docker (Linux). |

## Prerequisites

1. **Docker Desktop** (macOS) or **Docker Engine** (Linux) must be running.
2. **envsubst** must be available (`brew install gettext` on macOS).
3. **Install a worktree management tool (recommended).** The template works with raw `git worktree` commands, but tools like [git-wt](https://github.com/k1LoW/git-wt) provide a better experience with hook support.

## Directory Structure

```
myapp/                                   # main worktree
  .git/                                  # git database
  .worktree/                         # container-wt files
    Dockerfile.base                      # team-shared base image
    Dockerfile.app                       # default app image (FROM devbase)
    docker-compose.yml                   # per-worktree app service (base + app)
    docker-compose.local.yml             # personal overrides (gitignored, auto-stubbed)
    docker-compose.local.example.yml     # template for personal overrides (tracked)
    init.sh                              # host-side: resolves paths → .env, expands .env.app.template
    .env.app.template                    # per-worktree env var template (tracked in git)
    personal/example/Dockerfile          # example personal Dockerfile
    .env.app                             # generated by init.sh from template (gitignored)
  docker-compose.yml                     # shared infrastructure (Traefik, DB, cache)
  .env                                   # generated by init.sh (gitignored)
  .worktree/
    hooks/
      on-create.sh                       # host-side: runs after worktree creation
      on-delete.sh                       # host-side: cleanup hook
  .worktreeinclude                       # glob patterns for files to copy to new worktrees (tracked)
  .worktreeinclude.local                 # personal patterns (gitignored)
  src/
  ...

feature-x/                               # git worktree (sibling directory)
  .git                                   # file → ../myapp/.git/worktrees/feature-x
  .worktree/                             # same files (tracked in git)
  src/
  ...
```

## Configuration Files

### `docker-compose.yml` (project root)

Shared infrastructure services. Started independently on the host with `docker compose -f docker-compose.yml up -d`. Completely decoupled from app containers.

Uses `name: ${PROJECT_NAME:-myapp}-infra` to prevent Compose project name collision with app compose.

### `.worktree/docker-compose.yml`

Per-worktree app services with two-stage build:

- **`base` service:** Builds `Dockerfile.base`, tags as `${PROJECT_NAME}-dev-base:local`
- **`app` service:** Builds `Dockerfile.app` with `additional_contexts: devbase: service:base`

The `additional_contexts` ensures the base image is always built before the app image. Personal Dockerfiles also use `FROM devbase` — the context is provided by the compose file.

### `.worktree/docker-compose.local.yml` and `.worktree/docker-compose.local.example.yml`

Personal Docker Compose overrides (gitignored). Primary use case: override the app service's build to use a personal Dockerfile:

```yaml
services:
  app:
    build:
      context: ..
      dockerfile: .worktree/personal/ken/Dockerfile
      additional_contexts:
        devbase: "service:base"
```

### `.worktree/init.sh`

Runs on the **host** (called by the installer on first setup, and by `on-create.sh` for new worktrees). Resolves git paths, detects project name, sanitizes worktree name, detects branch name (falls back to short SHA on detached HEAD), creates `.worktree/docker-compose.local.yml` stub if missing, expands the env var template, and writes `.env` (with `COMPOSE_FILE`) for Docker Compose substitution. `COMPOSE_PROJECT_NAME` is intentionally NOT written to `.env` — each compose file sets its own project name via the top-level `name:` attribute.

### `.worktree/.env.app.template`

Per-worktree environment variable template. Tracked in git. Uses `${VARIABLE}` placeholders that `init.sh` expands via `envsubst`.

### `.worktreeinclude` and `.worktreeinclude.local`

Glob patterns (one per line) for gitignored files that should be copied from the main worktree to new worktrees.

### Dockerfile layering

```
.worktree/Dockerfile.base     — Team-shared: OS packages, git, curl, zsh, non-root user
      ↓ (FROM devbase)
.worktree/Dockerfile.app      — Project-specific: language runtimes, build tools, client libs
      ↓ (FROM devbase)
.worktree/personal/X/Dockerfile — Personal: editors, AI CLIs, shell configs
```

All Dockerfiles use `FROM devbase`. The named context is provided by `additional_contexts: devbase: service:base` in the compose file.

## Worktree Hooks

The template provides hook scripts in `.worktree/hooks/` that handle worktree lifecycle events. These scripts are **not called automatically** — users wire them into their worktree management tool of choice.

### `.worktree/hooks/on-create.sh`

Runs on the **host** after a new worktree is created. Copies gitignored files listed in `.worktreeinclude`, then runs `.worktree/init.sh` to generate `.env` files so the worktree is immediately ready.

### `.worktree/hooks/on-delete.sh`

Runs on the **host** before a worktree is removed. Stops the container and runs project-specific cleanup.

### Wiring Hooks to Worktree Tools

#### git-wt

```bash
git config --add wt.hook ".worktree/hooks/on-create.sh"
git config --add wt.deletehook ".worktree/hooks/on-delete.sh"
```

#### Raw `git worktree`

```bash
# Create
git worktree add ../myapp-feature-x -b feature-x
cd ../myapp-feature-x && .worktree/hooks/on-create.sh

# Delete
cd ../myapp-feature-x && .worktree/hooks/on-delete.sh
cd ../myapp && git worktree remove ../myapp-feature-x
```

## How the Git Fix Works

### The Problem

When you create a git worktree, git writes a `.git` **file** (not directory) in the worktree with an absolute host path:

```
gitdir: /Users/you/projects/myapp/.git/worktrees/feature-x
```

When mounted into a container, this host path doesn't exist. All git commands fail.

### The Solution (Same-Path Volume Mount)

The template mounts the git common directory at the same absolute host path inside the container:

```
Host: /Users/you/projects/myapp/.git/  →  Container: /Users/you/projects/myapp/.git/
```

The `.git` file is **never modified**. No symlink or post-start script needed.

## Workflows

### Initial Setup

```bash
git clone https://github.com/you/your-repo.git myapp
cd myapp

# Install the template (runs init.sh automatically)
curl -fsSL https://raw.githubusercontent.com/kenfdev/container-wt/main/install.sh | bash

# Configure worktree hooks (recommended)
git config --add wt.hook ".worktree/hooks/on-create.sh"
git config --add wt.deletehook ".worktree/hooks/on-delete.sh"

# Start infrastructure
docker compose -f docker-compose.yml up -d

# Start the app container
docker compose up -d --build

# Enter the container
docker compose exec app zsh
```

### Create a Feature Worktree

```bash
cd myapp
git wt feature-x           # or: git worktree add ../feature-x -b feature-x
cd ../feature-x
docker compose up -d --build
# Browser: http://feature-x.myapp.localhost
```

### PR Review Flow

```bash
cd myapp
git fetch origin
git wt feature-branch
cd ../feature-branch
docker compose up -d --build
# Browser: http://feature-branch.myapp.localhost

# Cleanup
docker compose down
cd ../myapp
git wt -d feature-branch
```

### Cleanup

```bash
cd ../feature-x
docker compose down
.worktree/hooks/on-delete.sh
cd ../myapp
git worktree remove ../feature-x
```

## Platform Considerations

### macOS (Docker Desktop)

- `*.localhost` resolves to `127.0.0.1` by default. Traefik subdomain routing works out of the box.
- `extra_hosts: host-gateway` maps to `host.docker.internal`.
- Performance: Use `:cached` volume mount flag for better file system performance.

### Linux (Native Docker)

- `*.localhost` resolution may require configuration. Use `/etc/hosts` or `dnsmasq`.
- `extra_hosts: host-gateway` maps to the Docker bridge gateway IP (typically `172.17.0.1`).

## Limitations

- **Infrastructure must be started separately.** Run `docker compose -f docker-compose.yml up -d` from the project root before starting app containers.
- **Name collision risk.** Branch name sanitization may cause collisions (e.g., `feature/login` and `feature-login` both become `feature-login`). Use distinct branch names.
- **GitHub Codespaces not supported.** Different constraints (no Traefik, no sibling worktrees). Out of scope.
