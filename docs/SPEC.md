# container-wt

A thin, opinionated template for seamless Docker + git worktree workflows. No devcontainer CLI or VS Code required. Worktree management is delegated to external tools (e.g., [git-wt](https://github.com/k1LoW/git-wt), [wtp](https://github.com/satococoa/wtp), or raw `git worktree`). This template focuses only on what those tools can't do: making containers work correctly with worktrees.

## Problem

Working with containers and git worktrees simultaneously is painful:

1. **Git context breaks inside containers.** A git worktree's `.git` is a file (not a directory) containing an absolute host path (e.g. `gitdir: /Users/you/repo/.git/worktrees/feature-x`). When the worktree is mounted into a container at a different path (e.g. `/workspaces/repo-feature-x`), this host path doesn't resolve. All git operations (`log`, `blame`, `status`) fail inside the container. Note: this problem is specific to worktrees — regular repos have a `.git` directory that gets mounted alongside the project and works fine.

2. **Port conflicts.** Each container maps ports to the host (e.g. `3000:3000`). Running multiple worktree containers simultaneously causes port binding conflicts.

3. **No shared infrastructure.** Each container typically spins up its own database, cache, etc. There's no built-in way to share these across worktrees or isolate data per worktree within a shared service.

4. **Gitignored files don't propagate.** When creating a worktree, git only checks out tracked files. Gitignored files (`.env`, `docker-compose.local.yml`, IDE configs) must be manually copied.

## Solution Overview

**container-wt** is a template-only approach that solves these problems using plain Docker Compose, Dockerfiles, and a `dev` wrapper script:

- **Git fix:** Mount the git common directory at the same absolute host path inside the container so the `.git` file's host path references resolve directly. No symlink or file mutation needed.
- **No port conflicts:** A per-project Traefik reverse proxy routes by subdomain (`feature-x.myapp.localhost`, using the branch name). No host port mapping needed per worktree. Traefik port is configurable.
- **Shared infrastructure:** Infrastructure services (database, cache, proxy) run from a standalone `docker-compose.yml` at the project root — started with `./dev infra` on the host. Per-worktree app containers join a shared Docker network.
- **Gitignored file propagation:** `.worktreeinclude` + `.worktreeinclude.local` define glob patterns for files to copy to new worktrees. Copying is handled by worktree tool hooks (e.g., `git-wt`'s `wt.hook`).
- **Per-worktree env vars:** A `.env.app.template` (tracked in git) with `${VARIABLE}` placeholders is expanded by `init.sh` into `.env.app` (gitignored) per worktree.
- **Dockerfile layering:** `Dockerfile.base` (team-shared) + `Dockerfile.app` (project-specific) + personal `.docker/dev/<name>/Dockerfile` for individual customization. All use `FROM devbase` with `additional_contexts` ensuring the base is always built first.
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
  │    docker-compose.yml   (infra — ./dev infra)    │
  │    docker-compose.app.yml  (app — ./dev up)      │
  │    Dockerfile.base / Dockerfile.app              │
  │    init.sh / dev                                 │
  │    src/                                          │
  │                                                  │
  │  myapp-feature-x/  (worktree)                    │
  │    .git  (file → myapp/.git/worktrees/feature-x) │
  │    docker-compose.app.yml  (tracked in git)      │
  │    src/                                          │
  │                                                  │
  └──────────────────────────────────────────────────┘

  Host: ./dev infra (from myapp/)
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
| Dockerfile layering | `Dockerfile.base` + `Dockerfile.app` + personal | Team-shared base, project-specific app, personal customization. All use `FROM devbase` with `additional_contexts` for build ordering. |
| Worktree management | External tools (git-wt, wtp, raw git worktree) | Template does NOT wrap `git worktree`. Users choose their preferred tool. Template provides hook scripts that any tool can call. |
| Port conflict solution | Traefik with subdomain routing | Single entry point, configurable port (default 80). Auto-discovers containers via Docker labels. Zero-config per worktree. |
| Routing pattern | Always `{branch}.{project}.localhost` | Consistent pattern using the git branch name. Main worktree gets `main.myapp.localhost`. |
| Container naming | Always `app-{project}-{worktree}` | Consistent pattern, no special-casing. |
| DX wrapper | `./dev` script | Simple bash wrapper for `docker compose` commands. Runs `init.sh` automatically. |
| Network isolation | Per-project Docker network (`devnet-{project}`) | Prevents container name collisions and unintended cross-project access. |
| Compose project naming | Infra: `{PROJECT_NAME}-infra`, App: `{PROJECT_NAME}-{BRANCH_NAME}` | Prevents COMPOSE_PROJECT_NAME collision between infra and app compose files. |
| Infra lifecycle | Standalone `docker-compose.yml` at project root | Infrastructure runs independently on the host via `./dev infra`. No devcontainer required. |
| Per-worktree env vars | `.env.app.template` expanded by `init.sh` | Tracked template with `${VARIABLE}` placeholders. `init.sh` renders it into `.env.app` (gitignored) per worktree via `envsubst`. |
| Personal Dockerfiles | `.docker/dev/<name>/Dockerfile` with `docker-compose.local.yml` override | Each developer can customize their image without touching shared files. Base image inheritance guaranteed via `additional_contexts`. |
| .env location | Project root (not `.devcontainer/`) | Docker Compose auto-reads `.env` from the directory where it's invoked. Simpler path management. |
| Worktree hooks | `.worktree/hooks/on-create.sh` and `on-delete.sh` | Prescribed hook scripts at a well-known location. Users wire them into their worktree tool of choice. |
| Worktreeinclude | `.worktreeinclude` + `.worktreeinclude.local` at repo root | Glob patterns for gitignored files to copy from main worktree to new worktrees. |
| Local compose overrides | `docker-compose.local.yml` at project root (gitignored) | Personal Docker Compose overrides. Example template tracked as `docker-compose.local.example.yml`. |
| Platform | macOS + Linux | Template works on both Docker Desktop (macOS) and native Docker (Linux). |

## Prerequisites

1. **Docker Desktop** (macOS) or **Docker Engine** (Linux) must be running.
2. **envsubst** must be available (`brew install gettext` on macOS).
3. **Install a worktree management tool (recommended).** The template works with raw `git worktree` commands, but tools like [git-wt](https://github.com/k1LoW/git-wt) provide a better experience with hook support.

## Directory Structure

```
myapp/                                   # main worktree
  .git/                                  # git database
  docker-compose.yml                     # shared infrastructure (Traefik, DB, cache)
  docker-compose.app.yml                 # per-worktree app service (base + app)
  docker-compose.local.yml               # personal overrides (gitignored, auto-stubbed)
  docker-compose.local.example.yml       # template for personal overrides (tracked)
  Dockerfile.base                        # team-shared base image
  Dockerfile.app                         # default app image (FROM devbase)
  .docker/dev/example/Dockerfile         # example personal Dockerfile
  init.sh                               # host-side: resolves paths → .env, expands .env.app.template
  dev                                    # wrapper script (./dev up, exec, down, infra, build)
  .env                                   # generated by init.sh (gitignored)
  .env.app                               # generated by init.sh from template (gitignored)
  .env.app.template                      # per-worktree env var template (tracked in git)
  .worktree/
    hooks/
      on-create.sh                       # host-side: runs after worktree creation
      on-delete.sh                       # host-side: cleanup hook
  .worktreeinclude                       # glob patterns for files to copy to new worktrees (tracked)
  .worktreeinclude.local                 # personal patterns (gitignored)
  src/
  ...

myapp-feature-x/                         # git worktree (sibling directory)
  .git                                   # file → ../myapp/.git/worktrees/feature-x
  docker-compose.app.yml                 # same files (tracked in git)
  Dockerfile.base                        # same files (tracked in git)
  Dockerfile.app                         # same files (tracked in git)
  .worktree/                             # same files (tracked in git)
  .env.app.template                      # same template (tracked in git)
  src/
  ...
```

## Configuration Files

### `docker-compose.yml` (project root)

Shared infrastructure services. Started independently on the host with `./dev infra`. Completely decoupled from app containers.

Uses `name: ${PROJECT_NAME:-myapp}-infra` to prevent Compose project name collision with app compose.

### `docker-compose.app.yml`

Per-worktree app services with two-stage build:

- **`base` service:** Builds `Dockerfile.base`, tags as `${PROJECT_NAME}-dev-base:local`
- **`app` service:** Builds `Dockerfile.app` with `additional_contexts: devbase: service:base`

The `additional_contexts` ensures the base image is always built before the app image. Personal Dockerfiles also use `FROM devbase` — the context is provided by the compose file.

### `docker-compose.local.yml` and `docker-compose.local.example.yml`

Personal Docker Compose overrides (gitignored). Primary use case: override the app service's build to use a personal Dockerfile:

```yaml
services:
  app:
    build:
      context: .
      dockerfile: .docker/dev/ken/Dockerfile
      additional_contexts:
        devbase: "service:base"
```

### `init.sh`

Runs on the **host** (called by `./dev up` automatically). Resolves git paths, detects project name, sanitizes worktree name, creates `docker-compose.local.yml` stub if missing, expands the env var template, and writes `.env` for Docker Compose substitution.

### `dev` wrapper script

Thin bash wrapper around `docker compose` for common tasks:

| Command | Compose files used | What it does |
|---|---|---|
| `./dev infra` | `docker-compose.yml` | Start Traefik + shared services |
| `./dev up` | `docker-compose.app.yml` + `docker-compose.local.yml` | Run init.sh, create network, start app container |
| `./dev exec` | `docker-compose.app.yml` + `docker-compose.local.yml` | Open shell in app container |
| `./dev build` | `docker-compose.app.yml` + `docker-compose.local.yml` | Rebuild app image |
| `./dev down` | `docker-compose.app.yml` + `docker-compose.local.yml` | Stop app container |
| `./dev logs` | `docker-compose.app.yml` + `docker-compose.local.yml` | Tail app container logs |

### `.env.app.template`

Per-worktree environment variable template. Tracked in git. Uses `${VARIABLE}` placeholders that `init.sh` expands via `envsubst`.

### `.worktreeinclude` and `.worktreeinclude.local`

Glob patterns (one per line) for gitignored files that should be copied from the main worktree to new worktrees.

### Dockerfile layering

```
Dockerfile.base          — Team-shared: OS packages, git, curl, zsh, non-root user
      ↓ (FROM devbase)
Dockerfile.app           — Project-specific: language runtimes, build tools, client libs
      ↓ (FROM devbase)
.docker/dev/X/Dockerfile — Personal: editors, AI CLIs, shell configs
```

All Dockerfiles use `FROM devbase`. The named context is provided by `additional_contexts: devbase: service:base` in the compose file.

## Worktree Hooks

The template provides hook scripts in `.worktree/hooks/` that handle worktree lifecycle events. These scripts are **not called automatically** — users wire them into their worktree management tool of choice.

### `.worktree/hooks/on-create.sh`

Runs on the **host** after a new worktree is created. Copies gitignored files listed in `.worktreeinclude`.

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

# Start infrastructure
./dev infra

# Configure worktree hooks (recommended)
git config --add wt.hook ".worktree/hooks/on-create.sh"
git config --add wt.deletehook ".worktree/hooks/on-delete.sh"

# Start the app container
./dev up

# Enter the container
./dev exec
```

### Create a Feature Worktree

```bash
cd myapp
git wt feature-x           # or: git worktree add ../myapp-feature-x -b feature-x
cd ../myapp-feature-x
./dev up
# Browser: http://feature-x.myapp.localhost
```

### PR Review Flow

```bash
cd myapp
git fetch origin
git wt feature-branch
cd ../myapp-feature-branch
./dev up
# Browser: http://feature-branch.myapp.localhost

# Cleanup
./dev down
cd ../myapp
git wt -d feature-branch
```

### Cleanup

```bash
cd ../myapp-feature-x
./dev down
.worktree/hooks/on-delete.sh
cd ../myapp
git worktree remove ../myapp-feature-x
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

- **Infrastructure must be started separately.** Run `./dev infra` from the project root before starting app containers.
- **Name collision risk.** Branch name sanitization may cause collisions (e.g., `feature/login` and `feature-login` both become `feature-login`). Use distinct branch names.
- **GitHub Codespaces not supported.** Different constraints (no Traefik, no sibling worktrees). Out of scope.
