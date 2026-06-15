# Workstation

A Docker-based multi-project workstation that provisions isolated, language-specific dev environments on demand using Docker-in-Docker and Dev Containers.

## Overview

The workstation container runs idle and exposes a single CLI tool — `wks` — to manage multiple projects. Each project lives in `workspace/<name>/` and gets its own devcontainer. You never touch the host machine's Docker socket or toolchain.

---

## Quickstart

```bash
# 1. Clone this repo
git clone <this-repo-url>
cd <repo>

# 2. Configure
cp .env.sample .env
# Edit .env: set ANTHROPIC_API_KEY, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, SSH_AUTH_SOCK

# 3. Create the workspace directory
mkdir workspace

# 4. Start the workstation
docker compose up --build -d

# 5. Enter the workstation
docker exec -it <workstation_container_name> bash -i

# 6. Bootstrap your first project
wks init git@github.com:user/repo.git

# Or interactively
wks init
```

---

## Requirements

- Docker and Docker Compose
- An active SSH agent on your host with keys loaded:
  ```bash
  ssh-add -l   # must list at least one key
  ```
- An Anthropic API key (for opencode)

---

## Environment variables

Copy `.env.sample` to `.env` and fill in the values.

### Required

| Variable | Description |
|---|---|
| `ANTHROPIC_API_KEY` | API key for opencode |
| `GIT_AUTHOR_NAME` | Git identity used inside the container |
| `GIT_AUTHOR_EMAIL` | Git identity used inside the container |
| `SSH_AUTH_SOCK` | Path to your host SSH agent socket |

Find your SSH socket path:
```bash
echo $SSH_AUTH_SOCK
```

### Optional

| Variable | Default | Description |
|---|---|---|
| `NODE_VERSION` | `22` | Node.js version in the workstation image |
| `DEVCONTAINER_CLI_VERSION` | `0.75.0` | Pinned `@devcontainers/cli` version |
| `FORWARD_PORT` | `5173` | Single port forwarded from workstation to host |

For multiple port forwards, use `compose.override.yaml`:
```yaml
services:
  workstation:
    ports:
      - "5173:5173"
      - "8080:8080"
```

---

## `wks` command reference

```
wks <command> [args]

Commands:
  init   [git-url] [options]     Bootstrap a new project (interactive if no args)
  open   <project> [subfolder]   Start devcontainer if needed, then launch opencode
  exec   <project> [subfolder]   Open a shell inside the devcontainer
  stop   <project> [subfolder]   Stop the devcontainer
  status [project]               Show project status (all projects if no argument)
  remove [--force] <project>     Remove project and stop its devcontainer
  help                           Show this help
```

### `wks init`

Clones a repository, auto-detects the project type, applies a devcontainer template if none exists, and runs `devcontainer up`.

```bash
wks init                                      # interactive prompts
wks init git@github.com:user/repo.git         # non-interactive
wks init git@github.com:user/repo.git \
  --name my-project \
  --template node \
  --no-up                                     # skip devcontainer up
```

Options:
- `-n, --name NAME` — project directory name (default: derived from URL)
- `-t, --template TYPE` — `node`, `php`, or `default` (default: auto-detect)
- `-s, --subfolder PATH` — subfolder in the repo for the devcontainer (default: `.`)
- `--no-up` — clone and apply template, but skip `devcontainer up`
- `--no-template` — skip template application even if no `.devcontainer` exists

### `wks open`

Starts the devcontainer if not running, then launches opencode in the project directory.

```bash
wks open my-project
wks open my-monorepo apps/api     # explicit subfolder
```

### `wks exec`

Opens a bash shell inside the running devcontainer.

```bash
wks exec my-project
```

The devcontainer must be running. Use `wks open` to start it first.

### `wks stop`

Stops the devcontainer.

```bash
wks stop my-project
```

### `wks status`

Lists all projects in `workspace/` with their current state.

```bash
wks status              # all projects
wks status my-project   # one project (detailed)
```

States: `running`, `stopped`, `no devcontainer`.

### `wks remove`

Stops the devcontainer and permanently deletes the project directory.

```bash
wks remove my-project            # prompts for confirmation
wks remove --force my-project    # no confirmation
```

---

## Workflow

```
wks init git@github.com:user/repo.git
    └── git clone → /workspace/<project>
    └── auto-detect template (package.json → node, composer.json → php, else → default)
    └── cp templates/<type>/.devcontainer → /workspace/<project>/
    └── devcontainer up --workspace-folder /workspace/<project>

wks open <project>
    └── devcontainer up (if not already running)
    └── opencode --cwd /workspace/<project>

wks exec <project>
    └── docker exec -it <container> /bin/bash -i

wks stop <project>
    └── devcontainer down --workspace-folder /workspace/<project>
```

---

## Architecture

```
Host machine
├── SSH agent (keys never leave the host)
└── Docker
    ├── workstation (this repo)
    │   ├── wks CLI
    │   ├── opencode
    │   └── @devcontainers/cli
    └── daemon (docker:dind sidecar)
        └── devcontainers (one per project)
            ├── workspace/project-a/  (node)
            ├── workspace/project-b/  (php)
            └── workspace/project-c/  (default)
```

**Docker-in-Docker with TLS** — the `daemon` service runs as a `docker:dind` container with TLS enabled (`tcp://daemon:2376`). Certificates are auto-generated by the daemon and shared with the workstation via a named volume. The host Docker socket is never mounted.

**Script hot-reload** — `scripts/` is bind-mounted into the workstation. `entrypoint.sh` creates symlinks from `scripts/*` into `/usr/local/bin/` at startup. Editing a script on the host takes effect immediately without rebuilding the image.

**Filesystem as project registry** — there is no database of projects. A directory in `workspace/` containing `.git` or `.devcontainer` is a valid project. `wks status` scans the filesystem directly.

**Devcontainer detection** — `wks` locates a running devcontainer by the label `devcontainer.local_folder=<path>` that the devcontainer CLI applies to every container it creates.

**opencode runs in the workstation** — not inside the devcontainer. This avoids TUI issues and keeps a consistent environment regardless of the project's language stack.

---

## Devcontainer templates

Templates in `templates/` are copied into the target repo by `wks init` only when no `.devcontainer/` exists.

| Template | Base image | Notes |
|---|---|---|
| `node` | `devcontainers/javascript-node:22-bullseye` | `safe-npm` symlinked as `npm`; `postCreateCommand` runs `npm install` |
| `php` | `devcontainers/php:8-bullseye` | Xdebug + IntelliSense extensions; port 8080 forwarded; `postCreateCommand` runs `composer install` if `composer.json` present |
| `default` | `devcontainers/base:debian` | No customizations; fallback for unknown project types |

---

## Troubleshooting

### SSH: `Permission denied (publickey)`

```
ssh-add -l
```
Must show at least one key. If empty:
```bash
ssh-add ~/.ssh/id_ed25519    # or your key path
```

Verify `SSH_AUTH_SOCK` in `.env` points to the live socket:
```bash
echo $SSH_AUTH_SOCK          # run this on your host, copy the value to .env
```

The socket path changes on some systems after logout/reboot. Always verify before `docker compose up`.

### SSH: socket path on macOS

On macOS, the SSH agent socket path is typically `/private/tmp/com.apple.launchd.*/Listeners`. Use:
```bash
echo $SSH_AUTH_SOCK
```

### Docker daemon not reachable

If the workstation fails to connect to the Docker daemon:
```bash
docker compose logs daemon
```
The daemon service runs a healthcheck (`docker info` every 3s). The workstation only starts once the daemon is healthy.

### `wks` not found

Ensure the `scripts/` directory is bind-mounted (it is, via `compose.yaml`). If running the container manually without compose, mount it:
```bash
docker run -v $(pwd)/scripts:/workspace_root/scripts ...
```

### Devcontainer up fails

Check the devcontainer logs:
```bash
docker compose logs workstation
```
Common causes: missing `.devcontainer/` in the project directory, Docker daemon not ready, network issues pulling the base image.

---

## FAQ

**Can I use this without an SSH agent (public repos)?**
Yes. Use HTTPS clone URLs (`https://github.com/user/repo.git`) in `wks init`. The SSH agent is only required for SSH clone URLs (`git@github.com:...`).

**Can I add my own devcontainer template?**
Yes. Add a directory under `templates/` with a `.devcontainer/` inside it. Use `wks init --template <your-template-name>` to apply it.

**Does `wks remove` delete the Docker image?**
No. It stops and removes the running devcontainer and deletes the project directory from `workspace/`. The Docker image used by the devcontainer remains in the `docker_cache` volume.

**How do I forward more than one port?**
Create a `compose.override.yaml` at the repo root:
```yaml
services:
  workstation:
    ports:
      - "5173:5173"
      - "8080:8080"
```

**How do I persist bash history?**
It is persisted automatically via the `workspace_bash_history` named volume. History survives `docker compose down && up`.

**How do I update `wks` or `entrypoint.sh`?**
Edit the files in `scripts/` directly on your host. Changes are live immediately — no rebuild needed. If you modify `entrypoint.sh`, restart the workstation container: `docker compose restart workstation`.

---

## License

MIT — see [LICENSE](LICENSE).
