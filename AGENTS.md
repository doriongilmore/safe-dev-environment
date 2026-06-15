# AGENTS.md

## What this repo is

A Docker-based **multi-project workstation** that provisions isolated, language-specific dev environments on demand. This is NOT an application codebase — there is no test suite, no linter, no build pipeline. The "code" is `scripts/entrypoint.sh`, `scripts/wks`, `Dockerfile`, `compose.yaml`, and devcontainer templates.

---

## Running the project

```bash
# One-time setup
cp .env.sample .env       # fill in values (see below)
mkdir workspace

# Launch
docker compose up --build

# Bootstrap your first project (inside the workstation container)
docker exec -it <workstation_container_name> bash -i
wks init git@github.com:user/repo.git

# Or interactively:
wks init

# Open a project (start devcontainer + launch opencode)
wks open <project>

# Other commands
wks exec <project>        # shell inside the devcontainer
wks stop <project>        # stop the devcontainer
wks status                # list all projects
wks remove <project>      # remove project with confirmation
wks help                  # full command reference
```

The workstation container idles (`tail -f /dev/null`) — `wks` manages the inner devcontainers.

---

## Required `.env` values

| Variable | Notes |
|---|---|
| `ANTHROPIC_API_KEY` | API key for opencode |
| `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` | Git identity used inside the container |
| `SSH_AUTH_SOCK` | Host SSH agent socket path (e.g. `/run/user/1000/ssh-agent.socket`) — **required for private repos** |

**Optional variables:**

| Variable | Default | Notes |
|---|---|---|
| `NODE_VERSION` | `22` | Node.js version in the workstation image |
| `DEVCONTAINER_CLI_VERSION` | `0.75.0` | Pinned `@devcontainers/cli` version |
| `FORWARD_PORT` | `5173` | Single port forwarded from workstation to host |

`SSH_AUTH_SOCK` is the most common failure point — `ssh-add -l` must show loaded keys before launching.

For multiple port forwards, use `compose.override.yaml`:
```yaml
services:
  workstation:
    ports:
      - "5173:5173"
      - "8080:8080"
```

---

## Architecture notes

- **Docker-in-Docker**: the `daemon` service is a `docker:dind` sidecar with **TLS enabled** (`tcp://daemon:2376`, auto-generated certs via `DOCKER_TLS_CERTDIR=/certs`). The workstation never uses the host Docker socket.
- **`workspace/`** is mounted into both `workstation` and `daemon` services — cloned repos are accessible from both.
- **Healthcheck on daemon**: `docker info` every 3s with a `service_healthy` gate — the workstation only starts once the daemon is confirmed ready.
- **`scripts/entrypoint.sh`** is the container ENTRYPOINT. It symlinks all files in `scripts/` into `/usr/local/bin/` at startup (hot-reload without rebuild), waits for TLS certs, waits for the daemon, then idles.
- **`scripts/wks`** is the main CLI, accessible via the symlink mechanism above. It absorbs the former `init-project.sh` logic.
- **Port forwarding** is parameterized via `FORWARD_PORT` (default `5173`). Not hardcoded.
- **`npm` → `safe-npm` symlink** (in the `node` template Dockerfile) applies at image build time — works in scripts AND interactive shells.
- **`.opencode/` is gitignored** and mounts to `/root/.config/opencode` inside the container via `OPENCODE_CONFIG_DIR`.
- **Bash history** persists across `docker compose down && up` via the `workspace_bash_history` named volume.

---

## Devcontainer templates

Templates in `templates/` are copied into the target repo by `wks init` only if no `.devcontainer/` exists there. Each template has a `Dockerfile` and a `scripts/post-create.sh`:

| Template | Base image | Notes |
|---|---|---|
| `node` | `devcontainers/javascript-node:22-bullseye` | `safe-npm` symlinked as `npm` in Dockerfile; `postCreateCommand` runs `npm install` |
| `php` | `devcontainers/php:8-bullseye` | Xdebug + IntelliSense extensions; port 8080 forwarded; `postCreateCommand` runs `composer install` if `composer.json` present |
| `default` | `devcontainers/base:debian` | No customizations; fallback for unknown project types |

---

## OpenCode / AIDD framework

The `.opencode/` directory contains an AIDD (AI-Driven Development) plugin framework — not application code.

**Entry points:**
- Master orchestrator skill: `aidd-dev-00-sdlc` → `/sdlc <request>` — runs the full spec→plan→implement→review→ship pipeline
- Onboarding: `aidd-context-00-onboard`

**SDLC flow is non-negotiable:** `spec (skippable) → plan → implement → review → ship`. Review must happen before ship.

**Commit discipline (implementer agent):**
- One atomic commit per ticked acceptance criterion checkbox
- Format: `<milestone-id>/<step>: <short description>` (Conventional Commits)
- Never stage: `node_modules/`, `dist/`, `.astro/`, coverage output, caches

**Plan file storage:** `aidd_docs/tasks/<yyyy_mm>/<yyyy_mm_dd>-<feature>.md`
- Scores ≥ 3 → master plan + child part files
- Scoring: breaking API changes (+3), DB migrations (+3), 3+ modules (+2), 5+ modules (+3), major refactor (+2), dep upgrades (+2)

**Memory bank:** `aidd_docs/memory/` — do not treat `aidd_docs/`, `AGENTS.md`, `CLAUDE.md`, or `.aidd/` as project architecture in memory files.

**Agents (in `.opencode/agents/`):**

| Agent | Model | Role |
|---|---|---|
| `aidd-dev-implementer` | sonnet | Writes code, commits per acceptance criterion |
| `aidd-dev-planner` | opus | Writes plans only — never writes code |
| `aidd-dev-reviewer` | opus | Read-only critic — never edits |

**MCP servers** (all currently disabled in `opencode.jsonc`): Playwright, Figma, Atlassian (Jira/Confluence).
