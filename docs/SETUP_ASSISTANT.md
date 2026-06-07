# container-wt Setup Assistant Guide

You are finalizing a project-specific `container-wt` installation.

Follow these rules strictly.

## Required First Steps

1. Read `docs/ARCHITECTURE.md`.
2. Inspect the target project before proposing changes.
3. Identify whether the installation mode is `simple` or `web`.
4. Review the files skipped or intentionally left unmodified during installation.
5. Propose a plan.
6. Ask the user for approval before editing any file.

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

## Files To Understand

Common files:

```text
.container/Dockerfile.example
.container/Dockerfile
.container/docker-compose.yml
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

## Simple Mode Procedure

Simple mode is CLI/container-shell first.

It should not expose ports by default.

When finalizing simple mode:

1. Detect the project stack.
   - Check files like `package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`, `requirements.txt`, `Gemfile`, `pom.xml`, `build.gradle`, `Makefile`, and README files.
2. Propose `.container/Dockerfile` changes.
   - Add only runtime/tooling needed by this project.
   - Keep the file understandable.
3. Review app runtime env needs.
   - Inspect `.env.example`, README docs, config files, and framework conventions.
   - Propose `.container/.env.app` changes only when needed.
4. Decide whether ports are needed.
   - If the project is truly CLI-only, keep ports absent.
   - If the user confirms a dev server is needed, propose a minimal `ports:` addition to `.container/docker-compose.yml`.
5. After approval and edits, verify:
   ```bash
   cd .container
   docker compose config
   ```
6. Provide start commands:
   ```bash
   cd .container
   docker compose up -d --build
   docker compose exec app zsh
   ```

## Web Mode Procedure

Web mode routes `http://localhost:9876` through Traefik to one active worktree app container.

When finalizing web mode:

1. Detect the project stack.
2. Propose `.container/Dockerfile` changes for the project runtime.
3. Identify the app's internal development port.
   - Default is `APP_PORT=3000`.
   - If the app uses another port, propose updating `.container/.env`.
4. Inspect root Compose files and root `.env`.
   - Check for `compose.yml`, `compose.yaml`, `docker-compose.yml`, `docker-compose.yaml`, `docker-compose.override.yml`, `docker-compose.override.yaml`, and `.env`.
5. If root `.env` exists, propose a minimal safe patch.
   - Ensure `COMPOSE_FILE` includes `docker-compose.infra.yml`.
   - Preserve existing Compose files already in `COMPOSE_FILE`.
   - Do not reference missing Compose files.
   - Ensure `COMPOSE_PROFILES` enables `infra` where intended.
6. If root `.env` does not exist, verify the generated one is appropriate.
7. Configure shared services only if confirmed.
   - `docker-compose.infra.yml` should have only Traefik active by default.
   - Add or uncomment Postgres, Redis, or other services only after user approval.
8. Review `.container/.env.app`.
   - Add runtime env values needed by the app.
   - Prefer shared service URLs when shared services are configured.
9. Verify Compose configs:
   ```bash
   docker compose config
   cd .container
   docker compose config
   ```
10. Provide start and route commands:
    ```bash
    docker compose up -d
    cd .container
    docker compose up -d --build
    cd ..
    .container/route.sh
    open http://localhost:9876
    ```

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
- proposed file edits
- risks or assumptions
- exact commands to verify

Then ask for approval before editing.

After edits, summarize:

- files changed
- why each file changed
- verification run
- remaining manual steps
