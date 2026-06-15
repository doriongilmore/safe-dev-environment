# AGENTS.md

## What this repo is

A Docker-based orchestrator that provisions isolated, language-specific dev environments from a Git URL. This is NOT an application codebase — there is no test suite, no linter, no build pipeline. The "code" is `bootstrap.sh`, `Dockerfile`, `compose.yaml`, and devcontainer templates.

---

## Running the project

```bash
# One-time setup
cp .env.sample .env       # fill in values (see below)
mkdir workspace

# Launch
docker compose up --build

# Enter the inner dev environment (NOT the orchestrator container)
docker exec -it <inner_container_name> /bin/bash -i
```

The orchestrator container idles (`tail -f /dev/null`) after bootstrap — you exec into the *inner* devcontainer, not the orchestrator itself.

---

## Required `.env` values

| Variable | Notes |
|---|---|
| `GIT_URL` | SSH URL of the repo to provision (e.g. `git@github.com:user/repo.git`) |
| `GIT_AUTHOR_NAME` / `GIT_AUTHOR_EMAIL` | Git identity used inside the container |
| `REPO_NAME` | Directory name created under `workspace/` |
| `TEMPLATE_TYPE` | `node`, `php`, or `default` — applied only if the repo has no `.devcontainer/` |
| `SSH_AUTH_SOCK` | Host SSH agent socket path (e.g. `/run/user/1000/ssh-agent.socket`) — **required for private repos** |
| `SUBFOLDER` | Optional subdirectory within the repo for the devcontainer (defaults to `.`) |

`SSH_AUTH_SOCK` is the most common failure point — `ssh-add -l` must show loaded keys before launching.

---

## Architecture notes

- **Docker-in-Docker**: the `daemon` service is a `docker:dind` sidecar with TLS disabled (`tcp://daemon:2375`, no auth). The orchestrator never uses the host Docker socket.
- **`workspace/`** is mounted into both `dev` and `daemon` services — the cloned repo is accessible from both.
- **`git pull` is commented out** in `bootstrap.sh` (line ~24) — if the repo already exists in `workspace/`, no update occurs. Pull manually if needed.
- **Port 5173** is hardcoded in `compose.yaml` for Vite-based projects. Other ports require a compose override.
- **`npm` → `safe-npm` alias** (in the `node` template) only applies in interactive bash sessions, not scripts.
- **`.opencode/` is gitignored** and mounts to `/root/.config/opencode` inside the container via `OPENCODE_CONFIG_DIR`.
- The `bootstrap.sh` lines that launch opencode are currently commented out (lines ~70–71).

---

## Devcontainer templates

Templates in `templates/` are copied into the target repo only if no `.devcontainer/` exists there:

| Template | Base image | Notes |
|---|---|---|
| `node` | `devcontainers/javascript-node:24-bullseye` | Installs `safe-npm`, aliases `npm`; `postCreateCommand` runs `safe-npm install` |
| `php` | `devcontainers/php:8-bullseye` | Xdebug + IntelliSense extensions; port 8080 forwarded |
| `default` | `devcontainers/base:debian` | No customizations; fallback |

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
