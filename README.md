# container-wt

Plain Docker Compose templates for container development in git worktrees.

The core fix: git worktree `.git` files contain absolute host paths. This template mounts the git common directory at the same absolute path inside the container, so `git status`, `git blame`, and related commands work without mutating `.git`.

## Modes

The installer asks which setup you want:

```text
simple  CLI/container shell. No ports or Traefik.
web     Traefik localhost route for a web app.
```

Use flags for automation:

```bash
./install.sh --simple
./install.sh --web
```

## Install

Run from your project root:

```bash
curl -fsSL https://raw.githubusercontent.com/kenfdev/container-wt/main/install.sh | bash
```

The installer copies common files plus the selected mode, runs `.container/init.sh`, then prints a prompt you can paste into a coding assistant for project-specific setup.

The printed prompt references:

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- [docs/SETUP_ASSISTANT.md](docs/SETUP_ASSISTANT.md)

Use those docs when asking an assistant to adapt the generic template to a specific project.

## Disk Usage

The app image is named per project, not per worktree:

```env
APP_IMAGE_NAME=container-wt-myapp-app
```

This lets multiple worktrees reuse the same development image by default. If one worktree needs a
different Dockerfile or toolchain, change `APP_IMAGE_NAME` in that worktree's `.container/.env`
before building.

Before deleting a worktree, the delete hook can remove the container:

```bash
.container/hooks/on-delete.sh
```

To also remove the shared app image:

```bash
.container/hooks/on-delete.sh --rmi
```

## Installed Layout

Both modes use:

```text
.container/
  Dockerfile.example
  Dockerfile              # gitignored, copied from example if missing
  docker-compose.yml
  init.sh
  .env                    # generated, gitignored
  .env.app.example
  .env.app                # gitignored, copied from example if missing
  hooks/
    on-create.sh
    on-delete.sh
.worktreeinclude
.dockerignore
```

Web mode also installs:

```text
docker-compose.infra.yml
.container/route.sh
.container/traefik/dynamic.yml  # generated, gitignored
```

## Simple Mode

Simple mode is for CLI tools, tests, agents, and projects that do not normally expose web ports.

Start:

```bash
cd .container
docker compose up -d --build
docker compose exec app zsh
```

No ports are mapped by default. If the project needs a port, add it to `.container/docker-compose.yml`.

## Web Mode

Web mode runs Traefik on localhost and routes one stable URL to the currently selected worktree app container:

```text
http://localhost:9876
```

Start infra from the repo root:

```bash
docker compose up -d
```

Start the app:

```bash
cd .container
docker compose up -d --build
```

Route localhost to the current worktree:

```bash
.container/route.sh
open http://localhost:9876
```

Route an explicit worktree:

```bash
.container/route.sh feature-x
.container/route.sh feature-x 5173
```

`route.sh` expects the target app container to already be running.
After writing the Traefik route config, it restarts the project Traefik container so route changes apply reliably on Docker Desktop for Mac.

## Root Compose In Web Mode

Web mode installs `docker-compose.infra.yml`. Infra services use the `infra` profile.

If root `.env` does not exist, init creates:

```env
COMPOSE_FILE=docker-compose.infra.yml
COMPOSE_PROFILES=infra
PROJECT_NAME=myapp
NETWORK_NAME=devnet-myapp
TRAEFIK_HOST=127.0.0.1
TRAEFIK_PORT=9876
```

If root `.env` already exists, it is not overwritten. Update it manually so `COMPOSE_FILE` includes `docker-compose.infra.yml` without dropping existing Compose files.

## Worktree Flow

Manual:

```bash
git worktree add ../feature-x -b feature-x
cd ../feature-x
.container/init.sh
```

All `.container` scripts can be run from anywhere inside the worktree. They resolve the worktree root from their own path before reading or writing files.

Optional hook automation:

```text
.container/hooks/on-create.sh
.container/hooks/on-delete.sh
```

`on-create.sh` copies files listed in `.worktreeinclude` and `.worktreeinclude.local`, then runs `.container/init.sh`.

## How Git Works In The Container

A worktree `.git` file points to real metadata with an absolute path:

```text
gitdir: /Users/you/myapp/.git/worktrees/feature-x
```

The app Compose file mounts both:

```text
current worktree -> /workspaces/<worktree>
git common dir   -> same absolute path inside the container
```

No symlink, `.git` rewrite, or startup patch is needed.
