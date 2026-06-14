# container-wt Specification

## Purpose

`container-wt` installs a small Docker Compose development environment that works correctly from git worktrees.

It is intentionally template-based. Installed projects should remain understandable as plain Docker Compose and shell scripts.

## Modes

Install mode is selected interactively by default:

- `simple`: CLI/container-shell first. No ports, no Traefik.
- `web`: Traefik file-provider routing to one active worktree app container.

Automation flags:

```bash
install.sh --simple
install.sh --web
```

No compatibility alias for `--slim` is provided.

## Template Layout

Source templates are organized as:

```text
template/
  common/
  simple/
  web/
```

The installer copies `common`, then copies the selected mode.

Mode-specific files intentionally duplicate small init logic. Do not add a stored mode file or a shared mode-aware init abstraction.

## Installed Common Files

```text
.container/
  Dockerfile.example
  Dockerfile
  .env
  .env.app.example
  .env.app
  hooks/
    on-create.sh
    on-delete.sh
.dockerignore
```

Generated/gitignored:

```text
.container/.env
.container/.env.app
.container/Dockerfile
.container/traefik/dynamic.yml
```

## Dockerfile Model

Tracked:

```text
.container/Dockerfile.example
```

Local:

```text
.container/Dockerfile
```

`init.sh` copies the example to the local Dockerfile only if missing. Compose builds `.container/Dockerfile`.

There is no base/local layering, no `BASE_IMAGE`, and no default local Compose override.

## Environment Model

`.container/.env` is generated per worktree and used by Docker Compose.

It always includes:

```env
COMPOSE_FILE=docker-compose.yml
PROJECT_NAME=...
WORKTREE_NAME=...
BRANCH_NAME=...
GIT_COMMON_DIR=...
LOCAL_WORKSPACE_FOLDER=...
```

Web mode also includes:

```env
NETWORK_NAME=...
APP_PORT=3000
```

`.container/.env.app.example` is tracked. `.container/.env.app` is copied from it if missing and then user-owned.

No `envsubst` is used.

## Simple Mode

Installed mode-specific files:

```text
.container/docker-compose.yml
.container/init.sh
```

Simple mode:

- uses Compose's default network
- maps no ports by default
- does not create root `.env`
- does not include `APP_PORT`

## Web Mode

Installed mode-specific files:

```text
.container/docker-compose.yml
.container/init.sh
.container/route.sh
docker-compose.infra.yml
```

Web mode:

- creates a shared external Docker network if missing
- creates `.container/traefik/`
- may create root `.env` only if missing
- routes `http://localhost:9876` to one active worktree app container

Root `.env` default when missing:

```env
COMPOSE_FILE=docker-compose.infra.yml
COMPOSE_PROFILES=infra
PROJECT_NAME=myapp
NETWORK_NAME=devnet-myapp
TRAEFIK_HOST=127.0.0.1
TRAEFIK_PORT=9876
```

Existing root `.env` is never overwritten. The installer prompt tells the user/LLM to merge `COMPOSE_FILE` safely.

## Web Infra Compose

Infra file:

```text
docker-compose.infra.yml
```

It must not be merged into `docker-compose.override.yml`.

Active infra services use:

```yaml
profiles:
  - infra
```

Traefik:

- binds `${TRAEFIK_HOST:-127.0.0.1}:${TRAEFIK_PORT:-9876}:80`
- uses file provider only
- does not mount the Docker socket
- has no dashboard exposed by default

## Routing

`route.sh` is web-only.

Usage:

```bash
.container/route.sh
.container/route.sh <worktree-name>
.container/route.sh <worktree-name> <app-port>
```

No argument routes the current worktree. Explicit arguments use `WORKTREE_NAME`, not branch name.

`route.sh`:

- requires the target app container to be running
- does not start or build containers
- resolves the main repo via `git rev-parse --git-common-dir`
- writes `${MAIN_REPO_DIR}/.container/traefik/dynamic.yml`
- generates a catch-all `PathPrefix(`/`)` route

## Naming

`PROJECT_NAME` defaults to the main repo directory, derived from the git common directory.

Names are sanitized with hyphens:

```text
feature/login -> feature-login
my_app -> my-app
```

## Hooks

Hooks are installed but not auto-wired.

`on-create.sh`:

- runs `.container/init.sh`

Copying ignored files into newly-created worktrees is intentionally outside container-wt. Prefer a worktree-focused tool such as `worktrunk`, configured to automatically copy the files the project needs from `.gitignore`.

`on-delete.sh`:

- loads `.container/.env`
- removes `app-${PROJECT_NAME}-${WORKTREE_NAME}`
- runs `git worktree prune`
- does not modify web routing

## Installer Safety

Managed template files can be overwritten, backed up and replaced, or skipped.

User-owned files are never overwritten:

- `.container/Dockerfile`
- `.container/.env.app`
- root `.env`
- existing project Compose files

Skipped/unmodified files are included in the final printed LLM setup prompt.
