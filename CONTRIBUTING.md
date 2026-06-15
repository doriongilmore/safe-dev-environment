# Contributing

Thank you for considering a contribution to this project. The guidelines below keep the codebase consistent and the CI green.

---

## Table of contents

- [Development setup](#development-setup)
- [Code standards](#code-standards)
  - [Shell scripts](#shell-scripts)
  - [Dockerfiles](#dockerfiles)
- [Adding a devcontainer template](#adding-a-devcontainer-template)
- [Pull request process](#pull-request-process)
- [Commit format](#commit-format)

---

## Development setup

```bash
git clone <this-repo-url>
cd <repo>
cp .env.sample .env    # fill in values
mkdir workspace
docker compose up --build
```

Install the linters locally to run them before pushing:

```bash
# shellcheck (https://github.com/koalaman/shellcheck)
# Debian/Ubuntu:
apt-get install shellcheck

# macOS:
brew install shellcheck

# hadolint (https://github.com/hadolint/hadolint)
# macOS:
brew install hadolint

# Linux (binary):
wget -qO /usr/local/bin/hadolint \
  https://github.com/hadolint/hadolint/releases/latest/download/hadolint-Linux-x86_64
chmod +x /usr/local/bin/hadolint
```

---

## Code standards

### Shell scripts

All scripts in `scripts/` must pass [shellcheck](https://github.com/koalaman/shellcheck) with no errors or warnings.

```bash
shellcheck scripts/entrypoint.sh
shellcheck scripts/wks
```

Rules that apply to all scripts:

- Start with `#!/bin/bash`
- Second line: `set -euo pipefail`
- Use `local` for all variables inside functions
- Quote all variable expansions: `"$var"`, `"${array[@]}"`
- Use `die()` for fatal errors (exits with code 1)
- Write error messages to stderr: `echo "..." >&2`
- Exit codes: `0` = success, `1` = user error, `2` = system error

### Dockerfiles

All Dockerfiles (`Dockerfile`, `templates/*/Dockerfile`, `templates/*/.devcontainer/Dockerfile`) must pass [hadolint](https://github.com/hadolint/hadolint) with no errors.

```bash
hadolint Dockerfile
hadolint templates/node/.devcontainer/Dockerfile
hadolint templates/php/.devcontainer/Dockerfile
hadolint templates/default/.devcontainer/Dockerfile
```

Rules that apply to all Dockerfiles:

- Pin base image tags (no bare `latest`)
- Use `--no-install-recommends` on all `apt-get install` calls
- Clean up apt cache in the same `RUN` layer: `&& rm -rf /var/lib/apt/lists/*`
- Use `ARG` before `FROM` for version pinning
- Combine related `RUN` steps into a single layer where it reduces image size

---

## Adding a devcontainer template

1. Create a new directory: `templates/<name>/.devcontainer/`

2. Required files:
   - `devcontainer.json` — must include `"build": { "dockerfile": "Dockerfile" }`
   - `Dockerfile` — must use a pinned base image tag

3. Optional files:
   - `scripts/post-create.sh` — runs after the devcontainer is created; referenced via `postCreateCommand` in `devcontainer.json`

4. Naming: use lowercase, no spaces (e.g., `python`, `go`, `ruby`)

5. Update the template table in `README.md` and `AGENTS.md`

6. Test locally:
   ```bash
   wks init --template <name> --no-up git@github.com:user/test-repo.git
   wks open test-repo
   ```

---

## Pull request process

1. Fork the repository and create a branch from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```

2. Make your changes. Run the linters before pushing:
   ```bash
   shellcheck scripts/entrypoint.sh scripts/wks
   hadolint Dockerfile
   hadolint templates/node/.devcontainer/Dockerfile
   hadolint templates/php/.devcontainer/Dockerfile
   hadolint templates/default/.devcontainer/Dockerfile
   docker compose config > /dev/null    # validate compose.yaml
   ```

3. Ensure `docker compose up --build` succeeds before opening the PR.

4. Open the pull request against `main`. The CI will run automatically.

5. A maintainer will review within a reasonable time. Address feedback, then request a re-review.

6. Squash-merge is preferred for small changes; merge commits for feature branches with meaningful history.

---

## Commit format

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short description>

[optional body]
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `ci`

Scopes: `wks`, `entrypoint`, `compose`, `dockerfile`, `templates`, `docs`, `ci`

Examples:
```
feat(wks): add --dry-run flag to wks init
fix(entrypoint): handle missing scripts directory gracefully
docs(readme): add FAQ entry for multi-port forwarding
ci: add hadolint check for template Dockerfiles
```
