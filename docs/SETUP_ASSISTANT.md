# container-wt Setup Assistant Guide

You are finalizing a project-specific `container-wt` installation.

Follow these rules strictly.

## Required First Steps

1. Read `docs/ARCHITECTURE.md`.
2. Inspect the target project before proposing changes.
3. Identify whether the installation mode is `simple` or `web`.
4. Review the files skipped or intentionally left unmodified during installation.
5. Check whether `~/.config/container-wt/personal-profile.md` exists.
   - If it exists, read it and treat it as reusable developer preference source material.
   - Do not copy it blindly; adapt only relevant preferences to the target project.
6. If the user voluntarily included extra Dockerfile or Compose snippets, treat them as source material to merge, not as replacements.
7. Propose a plan.
8. Ask the user for approval before editing any file.

Do not edit first.

## Core Constraints

- Do not overwrite user-owned files.
- Do not replace an existing root `.env`.
- Do not replace existing project Compose files.
- Do not introduce Dockerfile base/local layering.
- Do not add `envsubst`.
- Do not rename `.worktreeinclude`.
- Do not add default port mappings in simple mode unless the user confirms the project needs ports.
- Preserve existing Compose behavior when editing `COMPOSE_FILE`.
- Treat pasted personal Docker setup as source material to merge, not as a replacement for installed files.

## Files To Understand

Common files:

```text
.container/Dockerfile.example
.container/Dockerfile
.container/docker-compose.yml
.container/docker-compose.override.yml  # optional, gitignored, included by init.sh if present
.container/init.sh
.container/.env
.container/.env.app.example
.container/.env.app
.container/hooks/on-create.sh
.container/hooks/on-delete.sh
.worktreeinclude
```

Web-only files:

```text
docker-compose.infra.yml
.container/route.sh
.container/traefik/dynamic.yml
```

## Personal Profile and Docker Setup Merge Guidance

The user may have a personal profile at `~/.config/container-wt/personal-profile.md` and may
also voluntarily include a Dockerfile, Docker Compose file, or Compose snippet.
This content can include their preferred CLI tools, package managers, dotfiles, bind mounts,
cache directories, environment variables, sidecar services, or local networking preferences.
Do not ask for pasted Docker setup by default when a personal profile is present.

Use it as input when proposing project-specific changes:

- Extract durable developer preferences, such as installed tools, shell setup, package caches,
  mounts, and helper services.
- Prefer project-declared runtime versions over personal profile defaults.
- Cross-check those preferences against the detected project stack.
- Merge Dockerfile needs into `.container/Dockerfile`.
- Merge project-wide app-container Compose needs into `.container/docker-compose.yml`.
- Put personal, machine-local Compose preferences in `.container/docker-compose.override.yml` when appropriate.
- In web mode, merge shared infra services into `docker-compose.infra.yml` only when they are
  actually shared infrastructure and the user approves them.
- Put app runtime environment values in `.container/.env.app` when appropriate.
- Keep project-specific values from the pasted content only when they match the target project.
- Do not copy stale service names, image names, container names, project names, port bindings,
  volumes, user names, home directories, runtime versions, or paths blindly.
- Do not replace container-wt's generated `.container/.env`, routing, networks, or Compose file
  structure unless the change is explicitly needed and approved.

## Disk Usage Guidance

The app image is shared across worktrees by default through `APP_IMAGE_NAME`.

- Keep `APP_IMAGE_NAME=container-wt-${PROJECT_NAME}-app` when worktrees use the same development
  Dockerfile.
- Use a worktree-specific `APP_IMAGE_NAME` only when that worktree intentionally needs a different
  Dockerfile or incompatible toolchain.
- Prefer project-level package cache volumes when the project stack benefits from them, such as
  npm, pnpm, Cargo, Go, pip, or Bundler caches.
- Do not prune Docker build cache automatically during normal setup or worktree deletion. Build
  cache improves rebuild speed and should be removed only by explicit user action.

## Simple Mode Procedure

Simple mode is CLI/container-shell first.

It should not expose ports by default.

When finalizing simple mode:

1. Detect the project stack.
   - Check files like `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `requirements.txt`, `Gemfile`, `pom.xml`, `build.gradle`, `Makefile`, and README files.
2. Review any pasted personal Docker setup.
   - Identify personal tools, mounts, env, and services that should be adapted to this project.
   - Ignore entries that only made sense for another project.
3. Propose `.container/Dockerfile` changes.
   - Add only runtime/tooling needed by this project.
   - Keep the file understandable.
4. Review app runtime env needs.
   - Inspect `.env.example`, README docs, config files, and framework conventions.
   - Propose `.container/.env.app` changes only when needed.
5. Decide whether ports are needed.
   - If the project is truly CLI-only, keep ports absent.
   - If the user confirms a dev server is needed, propose a minimal `ports:` addition to `.container/docker-compose.yml`.
6. After approval and edits, verify:
   ```bash
   cd .container
   docker compose config
   ```
7. Provide start commands:
   ```bash
   cd .container
   docker compose up -d --build
   docker compose exec app zsh
   ```

## Web Mode Procedure

Web mode routes `http://localhost:9876` through Traefik to one active worktree app container.
`.container/route.sh` restarts the project Traefik container after writing route config so file-provider changes apply reliably on Docker Desktop for Mac.

When finalizing web mode:

1. Detect the project stack.
2. Review any pasted personal Docker setup.
   - Identify personal tools, mounts, env, and services that should be adapted to this project.
   - Ignore entries that only made sense for another project.
3. Propose `.container/Dockerfile` changes for the project runtime.
4. Identify the app's internal development port.
   - Default is `APP_PORT=3000`.
   - If the app uses another port, propose updating `.container/.env`.
5. Inspect root Compose files and root `.env`.
   - Check for `compose.yml`, `compose.yaml`, `docker-compose.yml`, `docker-compose.yaml`, `docker-compose.override.yml`, `docker-compose.override.yaml`, and `.env`.
6. If root `.env` exists, propose a minimal safe patch.
   - Ensure `COMPOSE_FILE` includes `docker-compose.infra.yml`.
   - Preserve existing Compose files already in `COMPOSE_FILE`.
   - Do not reference missing Compose files.
   - Ensure `COMPOSE_PROFILES` enables `infra` where intended.
7. If root `.env` does not exist, verify the generated one is appropriate.
8. Configure shared services only if confirmed.
   - `docker-compose.infra.yml` should have only Traefik active by default.
   - Add or uncomment Postgres, Redis, or other services only after user approval.
9. Review `.container/.env.app`.
   - Add runtime env values needed by the app.
   - Prefer shared service URLs when shared services are configured.
10. Verify Compose configs:
   ```bash
   docker compose config
   cd .container
   docker compose config
   ```
11. Provide start and route commands:
    ```bash
    docker compose up -d
    cd .container
    docker compose up -d --build
    ./route.sh
    open http://localhost:9876
    ```

All `.container` scripts can be run from anywhere inside the worktree. They resolve the worktree root from their own path before reading or writing files.

## Root COMPOSE_FILE Guidance

If root `.env` already has:

```env
COMPOSE_FILE=docker-compose.yml:docker-compose.override.yml
```

then propose:

```env
COMPOSE_FILE=docker-compose.yml:docker-compose.override.yml:docker-compose.infra.yml
```

If `docker-compose.override.yml` does not exist, do not add it.

If the project uses `compose.yml`, preserve that naming.

Never blindly replace `COMPOSE_FILE`.

## Response Format

When proposing changes, include:

- detected stack
- files inspected
- whether a personal profile was found
- relevant profile/pasted preferences to merge
- profile/pasted preferences intentionally ignored and why
- proposed file edits
- risks or assumptions
- exact commands to verify

Then ask for approval before editing.

After edits, summarize:

- files changed
- why each file changed
- verification run
- remaining manual steps
