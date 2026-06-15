# Plan d'implémentation — Workstation multi-projets

**Date** : 2026-06-14
**Statut** : Prêt pour implémentation
**Contexte** : Shift d'un orchestrateur `dev` mono-projet vers un `workstation` multi-projets.
**Sources** : Synthèse de big_pickle.md, deepseek_v4.md, mimo_v2.5.md, nemotron_3_ultra.md, north_mini_code.md

---

## Sommaire

- [Décisions architecture](#décisions-architecture)
- [Structure de fichiers finale](#structure-de-fichiers-finale)
- [Phase 1 — Core](#phase-1--core)
- [Phase 2 — Robustesse](#phase-2--robustesse)
- [Phase 3 — Open Source](#phase-3--open-source)
- [Détail d'implémentation par fichier](#détail-dimplémentation-par-fichier)
  - [compose.yaml](#composeyaml)
  - [Dockerfile](#dockerfile)
  - [scripts/entrypoint.sh](#scriptsentrypointsh)
  - [scripts/wks](#scriptswks)
  - [templates/node](#templatesnode)
  - [templates/php](#templatesphp)
  - [templates/default](#templatesdefault)
  - [.env.sample](#envsample)
  - [.gitignore](#gitignore)
  - [AGENTS.md](#agentsmd)

---

## Décisions architecture

| Décision | Choix | Justification |
|---|---|---|
| Nom du service | `workstation` | Cohérent avec le concept de poste de travail multi-projets |
| Nom de la commande CLI | `wks` | Court (3 chars), sans conflit système connu, abréviation naturelle de workstation |
| Script d'entrée | `scripts/entrypoint.sh` | `bootstrap.sh` supprimé — entrypoint déplacé dans `scripts/` pour cohérence |
| Scripts dans le PATH | Symlinks créés par `entrypoint.sh` : `/workspace_root/scripts/*` → `/usr/local/bin/` | `/workspace_root` est déjà monté, hot-reload sans rebuild, symlinks comme pont |
| Registre de projets | Aucun — filesystem comme source de vérité | `/workspace/<projet>` avec `.git` ou `.devcontainer` = projet valide. Pas de désynchronisation possible |
| Node dans le workstation | Oui, `ARG NODE_VERSION=22` | Nécessaire pour `@devcontainers/cli` via npm. Version fixée pour reproductibilité |
| devcontainer CLI | `npm install -g @devcontainers/cli@${DEVCONTAINER_CLI_VERSION}` | Version fixée via build arg |
| TLS DinD | Actif par défaut, génération automatique via `DOCKER_TLS_CERTDIR=/certs` | docker:dind génère les certificats seul, zéro friction utilisateur |
| Healthcheck daemon | `docker info` toutes les 3s | Permet `depends_on: condition: service_healthy`, plus propre que la boucle dans l'entrypoint |
| SSH_AUTH_SOCK | Requis dans compose.yaml, warning si socket absent | Principalement des repos privés. Warning clair plutôt qu'échec silencieux |
| Persistance | Named volume `workspace_bash_history` | History bash survit aux `down/up`. SSH known_hosts régénérés par ssh-keyscan à chaque démarrage |
| `wks open` | `devcontainer up` si nécessaire + `opencode --cwd <path>` depuis le workstation | opencode dans le workstation est plus stable pour les TUI qu'à l'intérieur du devcontainer |
| Détection devcontainer up | `docker ps` filtré sur le label `devcontainer.local_folder` | Label posé par devcontainer CLI sur chaque container créé |
| Subfolder auto-détection | Scan 1 niveau : si un seul sous-dossier avec `.devcontainer` → auto. Si plusieurs → erreur explicite | Zéro friction pour les monorepos simples |
| Interface bootstrap | `wks init` — intégré dans `wks` comme 7ème sous-commande | Cohérence totale : une seule commande à retenir. `wks help` expose tout |
| Comportement `wks` sans arg | Affiche `wks help` | Pattern standard des CLIs multi-commandes (git, docker, npm) |
| Mode interactif `wks init` | Prompts si `wks init` lancé sans argument, CLI avec flags sinon | Accessible aux nouveaux utilisateurs, scriptable avec flags |
| safe-npm | `ln -sf $(which safe-npm) /usr/local/bin/npm` dans le Dockerfile du template node | Fonctionne dans les scripts ET en interactif. Plus fiable qu'un alias ou un wrapper heredoc |
| Port | `${FORWARD_PORT:-5173}:${FORWARD_PORT:-5173}` — une seule paire | `compose.override.yaml` documenté pour multi-ports |
| Licence | MIT | Adoption maximale |

---

## Structure de fichiers finale

```
/
├── compose.yaml                        # workstation + daemon, TLS, healthcheck
├── Dockerfile                          # debian:bullseye-slim, Node ARG, devcontainer CLI ARG
├── scripts/
│   ├── entrypoint.sh                   # ENTRYPOINT : symlinks, git, TLS wait, daemon wait, idle
│   └── wks                             # CLI principal : init, open, exec, stop, status, remove, help
├── templates/
│   ├── node/
│   │   └── .devcontainer/
│   │       ├── devcontainer.json       # build: Dockerfile, postCreateCommand: scripts/post-create.sh
│   │       ├── Dockerfile              # javascript-node:22-bullseye, safe-npm wrapper
│   │       └── scripts/
│   │           └── post-create.sh     # safe-npm install
│   ├── php/
│   │   └── .devcontainer/
│   │       ├── devcontainer.json       # build: Dockerfile, postCreateCommand: scripts/post-create.sh
│   │       ├── Dockerfile              # php:8-bullseye
│   │       └── scripts/
│   │           └── post-create.sh     # composer install si composer.json présent
│   └── default/
│       └── .devcontainer/
│           ├── devcontainer.json       # build: Dockerfile
│           └── Dockerfile              # devcontainers/base:debian
├── .env.sample                         # Nouvelles variables, sans GIT_URL/REPO_NAME/SUBFOLDER/TEMPLATE_TYPE
├── .gitignore                          # Inchangé (workspace, .env, .opencode, .ocdata ignorés)
├── LICENSE                             # MIT
├── README.md                           # À réécrire en Phase 3
└── AGENTS.md                           # Mis à jour pour refléter le nouveau workflow
```

**Fichiers supprimés :**
- `bootstrap.sh` — remplacé par `scripts/entrypoint.sh`
- `scripts/init-project.sh` — logique absorbée dans `wks init`

---

## Phase 1 — Core

Le shift fonctionnel complet. À la fin de cette phase, le workstation est utilisable en multi-projets.

| # | Tâche | Fichiers | Critère de validation |
|---|---|---|---|
| 1.1 | `compose.yaml` — workstation, TLS, healthcheck, volumes | `compose.yaml` | `docker compose up --build` démarre sans erreur |
| 1.2 | `Dockerfile` — ARG versions, COPY scripts/, entrypoint | `Dockerfile` | Image build sans erreur, `wks help` disponible |
| 1.3 | `scripts/entrypoint.sh` — symlinks, git, TLS wait, daemon wait | `scripts/entrypoint.sh` | Container démarre, `docker version` fonctionne via TLS |
| 1.4 | `scripts/wks` — 7 sous-commandes + resolve_path | `scripts/wks` | `wks help` affiche toutes les commandes |
| 1.6 | Template node enrichi — Dockerfile + safe-npm + post-create.sh | `templates/node/` | `npm run` dans le devcontainer utilise safe-npm |
| 1.7 | Template php enrichi — Dockerfile + post-create.sh | `templates/php/` | `composer install` lancé automatiquement |
| 1.8 | Template default enrichi — Dockerfile | `templates/default/` | Cohérence structurelle avec node et php |
| 1.9 | `.env.sample` propre | `.env.sample` | Nouvelles variables documentées, anciennes supprimées |
| 1.10 | Supprimer `bootstrap.sh` | `bootstrap.sh` | Fichier absent du repo |
| 1.11 | `AGENTS.md` mis à jour | `AGENTS.md` | Reflète le nouveau workflow wks (init, open, exec, stop, status, remove) |

**Critères de succès Phase 1 :**
- `docker compose up --build` démarre workstation + daemon avec TLS
- `docker exec -it <workstation> bash` → `wks help` fonctionne
- `wks` sans argument → affiche `wks help`
- `wks init git@github.com:user/repo.git` clone, applique le bon template, lance `devcontainer up`
- `wks init` sans argument → mode interactif avec prompts
- `wks open <projet>` lance opencode dans le bon répertoire
- `wks exec <projet>` ouvre un shell dans le devcontainer
- `wks stop <projet>` arrête le devcontainer proprement
- `wks status` liste tous les projets avec leur état
- `wks remove <projet>` supprime le projet avec confirmation
- Le safe-npm wrapper fonctionne dans les scripts npm (pas seulement en interactif)
- L'history bash est persistante entre `docker compose down && up`

---

## Phase 2 — Robustesse

| # | Tâche | Détails |
|---|---|---|
| 2.1 | Validation SSH avant clone | `ssh-add -l` check dans `wks init` avant `git clone`. Message explicite si aucune clé chargée |
| 2.2 | Auto-detect template étendu | `go.mod` → go (template default pour l'instant), `Cargo.toml` → rust (idem), `requirements.txt` / `pyproject.toml` → python (idem) — préparation pour Phase future |
| 2.3 | Exit codes cohérents | Tous les scripts : 0 = succès, 1 = erreur utilisateur, 2 = erreur système. `set -euo pipefail` partout |
| 2.4 | Gestion FORWARD_PORT | Documentation `compose.override.yaml` pour multi-ports dans README + AGENTS.md |
| 2.5 | Healthcheck amélioré entrypoint | Timeout explicite sur l'attente TLS certs (30s max) et daemon (30s max) avec message d'erreur clair |
| 2.6 | `wks status` — détection état réel | Distinguer : projet connu (`.git`), devcontainer configuré (`.devcontainer`), devcontainer running (`docker ps`) |

---

## Phase 3 — Open Source

| # | Tâche | Détails |
|---|---|---|
| 3.1 | `LICENSE` MIT | Fichier officiel MIT avec année et auteur |
| 3.2 | `README.md` réécrit | Quickstart, architecture, workflow complet, troubleshooting SSH, FAQ |
| 3.3 | `CONTRIBUTING.md` | Standards shellcheck + hadolint, structure templates, PR process |
| 3.4 | CI GitHub Actions | Build image, shellcheck sur tous les scripts, hadolint sur tous les Dockerfiles |
| 3.5 | `SECURITY.md` | Explication TLS DinD, SSH agent forwarding, surface d'attaque |

---

## Détail d'implémentation par fichier

---

### `compose.yaml`

**Changements vs l'existant :**
- `dev` → `workstation`
- TLS activé sur daemon + workstation
- Healthcheck sur daemon
- `depends_on: condition: service_healthy`
- Suppression variables projet (GIT_URL, REPO_NAME, SUBFOLDER, TEMPLATE_TYPE)
- Ajout GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL
- Port dynamique `FORWARD_PORT`
- Named volume `workspace_bash_history`
- Volume TLS `certs-client` partagé entre daemon et workstation

```yaml
services:
  workstation:
    build:
      context: .
      args:
        NODE_VERSION: ${NODE_VERSION:-22}
        DEVCONTAINER_CLI_VERSION: ${DEVCONTAINER_CLI_VERSION:-0.75.0}
    volumes:
      - ./.opencode:/root/.config/opencode
      - ./.ocdata:/root/.local/share/opencode
      - .:/workspace_root
      - ./workspace:/workspace
      - ./templates:/templates:ro
      - ${SSH_AUTH_SOCK}:/tmp/ssh-agent.sock
      - workspace_bash_history:/root/.bash_history
      - certs-client:/certs/client:ro
    ports:
      - "${FORWARD_PORT:-5173}:${FORWARD_PORT:-5173}"
    environment:
      - DOCKER_HOST=tcp://daemon:2376
      - DOCKER_TLS_VERIFY=1
      - DOCKER_CERT_PATH=/certs/client
      - SSH_AUTH_SOCK=/tmp/ssh-agent.sock
      - GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME}
      - GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
    depends_on:
      daemon:
        condition: service_healthy

  daemon:
    image: docker:dind
    privileged: true
    environment:
      - DOCKER_TLS_CERTDIR=/certs
    volumes:
      - ./workspace:/workspace
      - docker_cache:/var/lib/docker
      - certs-client:/certs/client
    healthcheck:
      test: ["CMD", "docker", "info"]
      interval: 3s
      timeout: 5s
      retries: 10
      start_period: 5s

volumes:
  docker_cache:
  workspace_bash_history:
  certs-client:
```

**Notes :**
- `DOCKER_TLS_CERTDIR=/certs` sur le daemon déclenche la génération automatique des certificats au démarrage. Le daemon écrit dans `/certs/client/`, le workstation le monte en `:ro`.
- Le volume `certs-client` est nommé (pas un bind mount) — les certificats ne sont pas exposés sur l'hôte, uniquement entre les deux services.
- `workspace_bash_history` est un named volume : Docker gère son cycle de vie. Il persiste même après `docker compose down`.
- Le healthcheck utilise `docker info` (plus fiable que `docker version` pour vérifier que le daemon accepte des connexions).
- `start_period: 5s` laisse le temps au daemon de démarrer avant que les retries commencent.

---

### `Dockerfile`

**Changements vs l'existant :**
- Ajout `ARG NODE_VERSION` et `ARG DEVCONTAINER_CLI_VERSION`
- Version devcontainer CLI fixée
- `COPY scripts/` dans `/usr/local/bin/` supprimé — les symlinks sont créés au runtime par `entrypoint.sh`
- `bootstrap.sh` remplacé par `scripts/entrypoint.sh`
- Ajout `bash-completion` pour UX

```dockerfile
ARG DEBIAN_VERSION=bullseye-slim
FROM debian:${DEBIAN_VERSION}

ENV DEBIAN_FRONTEND=noninteractive

# Dépendances système minimales
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    openssh-client \
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI
RUN mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/debian/gpg \
       | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
       https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
       | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Node.js (version via build arg)
ARG NODE_VERSION=22
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# @devcontainers/cli (version fixée via build arg)
ARG DEVCONTAINER_CLI_VERSION=0.75.0
RUN npm install -g @devcontainers/cli@${DEVCONTAINER_CLI_VERSION}

# opencode
RUN curl -fsSL https://opencode.ai/install | bash -

# SSH known hosts pré-trustés
RUN mkdir -p -m 0700 ~/.ssh \
    && ssh-keyscan github.com gitlab.com bitbucket.org >> ~/.ssh/known_hosts 2>/dev/null

ENV OPENCODE_CONFIG_DIR=/root/.config/opencode
WORKDIR /workspace

COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
```

**Notes :**
- Seul `entrypoint.sh` est COPYé dans l'image — `wks` est accessible via `/workspace_root/scripts/` (bind mount) et symlinkéau runtime.
- Si le container démarre sans le mount (cas edge), `wks` ne sera pas disponible — c'est acceptable, le mount est toujours présent en usage normal.
- `--no-install-recommends` sur toutes les installations apt.
- `bash-completion` améliore l'UX dans le shell interactif.

---

### `scripts/entrypoint.sh`

**Rôle** : Point d'entrée du container. Crée les symlinks, configure git, attend les certificats TLS, attend le daemon, puis idle.

```bash
#!/bin/bash
set -euo pipefail

# ── Couleurs ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[workstation]${NC} $1"; }
warn() { echo -e "${YELLOW}[workstation]${NC} $1"; }
err()  { echo -e "${RED}[workstation]${NC} $1" >&2; }

# ── Symlinks scripts → PATH ──────────────────────────────────────────────────
# /workspace_root est le bind mount de . (racine du repo)
# Les scripts sont disponibles à l'édition depuis l'hôte et dans le PATH via symlinks
SCRIPTS_DIR="/workspace_root/scripts"
if [ -d "$SCRIPTS_DIR" ]; then
    for script in "$SCRIPTS_DIR"/*; do
        name=$(basename "$script")
        target="/usr/local/bin/$name"
        if [ ! -L "$target" ]; then
            ln -sf "$script" "$target"
            chmod +x "$script"
        fi
    done
    log "Scripts linked from $SCRIPTS_DIR"
else
    warn "Scripts directory not found at $SCRIPTS_DIR — wks unavailable"
fi

# ── Git identity ─────────────────────────────────────────────────────────────
git config --global --add safe.directory "*" 2>/dev/null || true
[ -n "${GIT_AUTHOR_NAME:-}"  ] && git config --global user.name  "$GIT_AUTHOR_NAME"
[ -n "${GIT_AUTHOR_EMAIL:-}" ] && git config --global user.email "$GIT_AUTHOR_EMAIL"

# ── SSH agent check ──────────────────────────────────────────────────────────
if [ ! -S "/tmp/ssh-agent.sock" ]; then
    warn "SSH agent socket not available at /tmp/ssh-agent.sock"
    warn "Private repos will fail. Ensure SSH_AUTH_SOCK is set in .env"
    warn "Public repos via HTTPS are unaffected."
fi

# ── Attente certificats TLS ──────────────────────────────────────────────────
# docker:dind génère les certs dans /certs/client/ au démarrage
# On attend qu'ils soient disponibles avant de tenter la connexion
TLS_CERT_PATH="${DOCKER_CERT_PATH:-/certs/client}"
if [ "${DOCKER_TLS_VERIFY:-0}" = "1" ]; then
    log "Waiting for TLS certificates at $TLS_CERT_PATH ..."
    MAX_TLS_WAIT=30
    elapsed=0
    until [ -f "${TLS_CERT_PATH}/ca.pem" ] && [ -f "${TLS_CERT_PATH}/cert.pem" ] && [ -f "${TLS_CERT_PATH}/key.pem" ]; do
        if [ $elapsed -ge $MAX_TLS_WAIT ]; then
            err "TLS certificates not available after ${MAX_TLS_WAIT}s. Check daemon logs."
            exit 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    log "TLS certificates ready."
fi

# ── Attente daemon Docker ────────────────────────────────────────────────────
# Le healthcheck compose assure que le daemon est up avant ce container,
# mais on garde une vérification locale pour les edge cases
log "Verifying Docker daemon connection..."
MAX_DOCKER_WAIT=30
elapsed=0
until docker info > /dev/null 2>&1; do
    if [ $elapsed -ge $MAX_DOCKER_WAIT ]; then
        err "Docker daemon not reachable after ${MAX_DOCKER_WAIT}s."
        err "DOCKER_HOST=${DOCKER_HOST:-not set}"
        exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
log "Docker daemon ready. (${DOCKER_HOST})"

# ── Banner ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}  Workstation ready.${NC}"
echo -e "  ${GREEN}wks init${NC}          Bootstrap a new project"
echo -e "  ${GREEN}wks help${NC}          Manage running projects"
echo ""

# ── Idle ─────────────────────────────────────────────────────────────────────
exec tail -f /dev/null
```

**Notes :**
- La boucle symlinks est idempotente — si un symlink existe déjà, il est ignoré. Permet les restarts sans erreur.
- `set -euo pipefail` : `-u` détecte les variables non définies, `-o pipefail` propage les erreurs dans les pipes.
- Le `exec tail -f /dev/null` remplace le processus shell par tail — tail devient PID 1, les signaux (SIGTERM) sont gérés proprement.
- Les deux boucles d'attente (TLS + daemon) ont un timeout explicite de 30s pour éviter les boucles infinies.
- Le healthcheck compose (`depends_on: service_healthy`) devrait théoriquement rendre la boucle daemon superflue, mais on la garde comme filet de sécurité.

---

### `scripts/wks`

**Rôle** : Interface principale. 7 sous-commandes. Fonction `resolve_path` partagée. Absorbe la logique de `init-project.sh`.

**Interface :**
```
wks [command] [args]

Commands:
  init    [git-url] [options]     Bootstrap a new project (interactive if no args)
  open    <project> [subfolder]   Start devcontainer if needed, then launch opencode
  exec    <project> [subfolder]   Open a shell inside the devcontainer
  stop    <project> [subfolder]   Stop the devcontainer
  status  [project]               Show status of one project or all projects
  remove  <project>               Remove project directory and stop its devcontainer
  help                            Show this help

wks without arguments → wks help
```

```bash
#!/bin/bash
set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

die()  { echo -e "${RED}Error:${NC} $1" >&2; exit 1; }
info() { echo -e "${GREEN}→${NC} $1"; }
warn() { echo -e "${YELLOW}⚠${NC} $1"; }

WORKSPACE="/workspace"

# ── resolve_path ──────────────────────────────────────────────────────────────
# Résout le chemin effectif du workspace-folder pour un projet.
# Logique :
#   1. Si subfolder fourni → base/subfolder (pas de vérification, l'utilisateur sait ce qu'il fait)
#   2. Si base/.devcontainer existe → base
#   3. Scan 1 niveau : sous-dossiers avec .devcontainer
#      - 0 trouvé  → erreur
#      - 1 trouvé  → auto-sélection avec avertissement
#      - 2+ trouvés → erreur, demander de préciser
#
# Usage : path=$(resolve_path <project> [subfolder])
# Affiche le chemin sur stdout. Messages d'info sur stderr.
resolve_path() {
    local project="$1"
    local subfolder="${2:-}"
    local base="${WORKSPACE}/${project}"

    [ -d "$base" ] || die "Project directory not found: $base"

    if [ -n "$subfolder" ]; then
        echo "${base}/${subfolder}"
        return
    fi

    if [ -d "${base}/.devcontainer" ]; then
        echo "$base"
        return
    fi

    # Scan 1 niveau
    local candidates=()
    for d in "${base}"/*/; do
        [ -d "${d}.devcontainer" ] && candidates+=("$d")
    done

    case ${#candidates[@]} in
        0)
            die "No .devcontainer found in '${project}'.
  Run: wks init to apply a template, or specify a subfolder:
  wks <command> ${project} <subfolder>"
            ;;
        1)
            local name
            name=$(basename "${candidates[0]%/}")
            warn "Auto-detected subfolder: ${name}" >&2
            echo "${candidates[0]%/}"
            ;;
        *)
            local list=""
            for c in "${candidates[@]}"; do list+="  - $(basename "${c%/}")\n"; done
            die "Multiple subfolders with .devcontainer found in '${project}'.
  Specify one:
$(printf "$list")  wks <command> ${project} <subfolder>"
            ;;
    esac
}

# ── find_devcontainer_container ───────────────────────────────────────────────
# Trouve le container Docker créé par devcontainer CLI pour un workspace-folder.
# devcontainer CLI pose le label devcontainer.local_folder=<path> sur le container.
# Retourne le container ID ou vide si non trouvé.
find_devcontainer_container() {
    local workdir="$1"
    docker ps -q --filter "label=devcontainer.local_folder=${workdir}" 2>/dev/null || true
}

# ── is_devcontainer_running ───────────────────────────────────────────────────
is_devcontainer_running() {
    local workdir="$1"
    local container_id
    container_id=$(find_devcontainer_container "$workdir")
    [ -n "$container_id" ]
}

# ── cmd_open ──────────────────────────────────────────────────────────────────
# Démarre le devcontainer si nécessaire, puis lance opencode dans le répertoire
# du projet depuis le workstation (pas depuis l'intérieur du devcontainer).
cmd_open() {
    local project="${1:-}"
    local subfolder="${2:-}"
    [ -z "$project" ] && die "Usage: wks open <project> [subfolder]"

    local workdir
    workdir=$(resolve_path "$project" "$subfolder")

    if is_devcontainer_running "$workdir"; then
        info "Devcontainer already running for '${project}'"
    else
        info "Starting devcontainer for '${project}'..."
        devcontainer up --workspace-folder "$workdir"
        info "Devcontainer started."
    fi

    info "Launching opencode in ${workdir}..."
    opencode --cwd "$workdir"
}

# ── cmd_exec ──────────────────────────────────────────────────────────────────
# Ouvre un shell bash interactif dans le devcontainer du projet.
# Utilise docker exec directement (plus stable que devcontainer exec pour les TUI).
cmd_exec() {
    local project="${1:-}"
    local subfolder="${2:-}"
    [ -z "$project" ] && die "Usage: wks exec <project> [subfolder]"

    local workdir
    workdir=$(resolve_path "$project" "$subfolder")

    local container_id
    container_id=$(find_devcontainer_container "$workdir")
    [ -z "$container_id" ] && die "Devcontainer for '${project}' is not running.
  Start it first: wks open ${project}"

    info "Entering devcontainer for '${project}'..."
    docker exec -it "$container_id" /bin/bash -i
}

# ── cmd_stop ──────────────────────────────────────────────────────────────────
cmd_stop() {
    local project="${1:-}"
    local subfolder="${2:-}"
    [ -z "$project" ] && die "Usage: wks stop <project> [subfolder]"

    local workdir
    workdir=$(resolve_path "$project" "$subfolder")

    if ! is_devcontainer_running "$workdir"; then
        warn "Devcontainer for '${project}' is not running."
        return 0
    fi

    info "Stopping devcontainer for '${project}'..."
    devcontainer down --workspace-folder "$workdir"
    info "Stopped."
}

# ── cmd_status ────────────────────────────────────────────────────────────────
# Sans argument : liste tous les projets dans /workspace/ avec leur état.
# Avec argument : détail d'un projet spécifique.
#
# États possibles :
#   running   — devcontainer container en cours d'exécution
#   stopped   — .devcontainer présent mais container arrêté
#   no-dc     — pas de .devcontainer (projet cloné sans template)
#
# Détection du type via les fichiers de config du projet.
cmd_status() {
    local project="${1:-}"

    if [ -n "$project" ]; then
        # Mode détail
        local base="${WORKSPACE}/${project}"
        [ -d "$base" ] || die "Project '${project}' not found in ${WORKSPACE}"

        echo -e "${BOLD}Project: ${project}${NC}"
        echo -e "  Path:   ${base}"

        # Type
        local ptype="unknown"
        [ -f "${base}/package.json" ]   && ptype="node"
        [ -f "${base}/composer.json" ]  && ptype="php"
        [ -f "${base}/go.mod" ]         && ptype="go"
        [ -f "${base}/Cargo.toml" ]     && ptype="rust"
        [ -f "${base}/requirements.txt" ] || [ -f "${base}/pyproject.toml" ] && ptype="python"
        echo -e "  Type:   ${ptype}"

        # Devcontainer
        if [ -d "${base}/.devcontainer" ]; then
            local workdir
            workdir=$(resolve_path "$project" "" 2>/dev/null || echo "$base")
            if is_devcontainer_running "$workdir"; then
                local cid
                cid=$(find_devcontainer_container "$workdir")
                echo -e "  Status: ${GREEN}running${NC} (container: ${cid:0:12})"
            else
                echo -e "  Status: ${YELLOW}stopped${NC}"
            fi
        else
            echo -e "  Status: ${YELLOW}no devcontainer${NC} (run: wks init to apply a template)"
        fi
    else
        # Mode liste tous projets
        echo -e "${BOLD}Projects in ${WORKSPACE}:${NC}"
        echo ""

        local found=0
        for dir in "${WORKSPACE}"/*/; do
            [ -d "$dir" ] || continue
            [ -d "${dir}.git" ] || [ -d "${dir}.devcontainer" ] || continue

            local name
            name=$(basename "$dir")
            found=$((found + 1))

            # État devcontainer
            local status_str="${YELLOW}no devcontainer${NC}"
            if [ -d "${dir}.devcontainer" ]; then
                if is_devcontainer_running "${dir%/}"; then
                    status_str="${GREEN}running${NC}"
                else
                    status_str="${YELLOW}stopped${NC}"
                fi
            fi

            # Type (détection rapide)
            local ptype="-"
            [ -f "${dir}package.json" ]   && ptype="node"
            [ -f "${dir}composer.json" ]  && ptype="php"
            [ -f "${dir}go.mod" ]         && ptype="go"
            [ -f "${dir}Cargo.toml" ]     && ptype="rust"

            printf "  %-25s %-8s %b\n" "$name" "$ptype" "$status_str"
        done

        if [ $found -eq 0 ]; then
            warn "No projects found in ${WORKSPACE}"
            echo "  Run 'wks init' to bootstrap your first project."
        else
            echo ""
            echo -e "  ${found} project(s) found."
        fi
    fi
}

# ── cmd_remove ────────────────────────────────────────────────────────────────
# Supprime un projet : arrête le devcontainer s'il tourne, supprime le dossier.
# Demande confirmation sauf si --force.
cmd_remove() {
    local project="${1:-}"
    local force=false
    [ "$project" = "--force" ] && { force=true; project="${2:-}"; }
    [ -z "$project" ] && die "Usage: wks remove [--force] <project>"

    local base="${WORKSPACE}/${project}"
    [ -d "$base" ] || die "Project '${project}' not found in ${WORKSPACE}"

    if [ "$force" = false ]; then
        echo -e "${RED}Warning:${NC} This will permanently delete ${base}"
        echo -n "Are you sure? [y/N] "
        read -r confirm
        [[ "$confirm" =~ ^[yY]$ ]] || { echo "Aborted."; exit 0; }
    fi

    # Arrêter le devcontainer si en cours
    if [ -d "${base}/.devcontainer" ]; then
        local workdir
        workdir=$(resolve_path "$project" "" 2>/dev/null || echo "$base")
        if is_devcontainer_running "$workdir"; then
            info "Stopping devcontainer for '${project}'..."
            devcontainer down --workspace-folder "$workdir" 2>/dev/null || true
        fi
    fi

    # Supprimer le répertoire
    info "Removing ${base}..."
    rm -rf "$base"
    info "Project '${project}' removed."
}

# ── cmd_help ──────────────────────────────────────────────────────────────────
cmd_help() {
    echo ""
    echo -e "${BOLD}wks — Workstation project manager${NC}"
    echo ""
    echo -e "${CYAN}Usage:${NC} wks <command> [args]"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo -e "  ${GREEN}init${NC}   [git-url] [options]     Bootstrap a new project (interactive if no args)"
    echo -e "  ${GREEN}open${NC}   <project> [subfolder]   Start devcontainer if needed, launch opencode"
    echo -e "  ${GREEN}exec${NC}   <project> [subfolder]   Open a shell inside the devcontainer"
    echo -e "  ${GREEN}stop${NC}   <project> [subfolder]   Stop the devcontainer"
    echo -e "  ${GREEN}status${NC} [project]               Show project status (all if no project given)"
    echo -e "  ${GREEN}remove${NC} [--force] <project>     Remove project and stop its devcontainer"
    echo -e "  ${GREEN}help${NC}                           Show this help"
    echo ""
    echo -e "${CYAN}Examples:${NC}"
    echo -e "  wks init                             # Interactive bootstrap"
    echo -e "  wks init git@github.com:user/repo    # Bootstrap with URL"
    echo -e "  wks open omni-tools                  # Start devcontainer + opencode"
    echo -e "  wks open my-monorepo apps/api        # With explicit subfolder"
    echo -e "  wks exec omni-tools                  # Shell in devcontainer"
    echo -e "  wks stop omni-tools                  # Stop devcontainer"
    echo -e "  wks status                           # List all projects"
    echo -e "  wks status omni-tools                # Detail for one project"
    echo -e "  wks remove omni-tools                # Remove with confirmation"
    echo -e "  wks remove --force omni-tools        # Remove without confirmation"
    echo ""
}

# ── Router ────────────────────────────────────────────────────────────────────
CMD="${1:-}"
shift || true

case "$CMD" in
    init)    cmd_init   "$@" ;;
    open)    cmd_open   "$@" ;;
    exec)    cmd_exec   "$@" ;;
    stop)    cmd_stop   "$@" ;;
    status)  cmd_status "$@" ;;
    remove)  cmd_remove "$@" ;;
    help|--help|-h|"") cmd_help ;;
    *)
        err "Unknown command: ${CMD}"
        cmd_help
        exit 1
        ;;
esac
```

**Notes :**
- La fonction `resolve_path` écrit ses messages d'info/warn sur **stderr** et le chemin sur **stdout** — ce qui permet le pattern `workdir=$(resolve_path ...)` sans capturer les messages.
- `find_devcontainer_container` utilise le label `devcontainer.local_folder` posé automatiquement par le devcontainer CLI — pas de registre nécessaire.
- `cmd_exec` utilise `docker exec -it` et non `devcontainer exec` — plus fiable pour les shells interactifs et les TUI.
- `cmd_remove` avec `--force` est le premier argument, géré avant de parser le projet — interface cohérente avec `docker rm -f`.
- `wks` sans argument tombe dans le cas `""` du router → `cmd_help`. Pattern identique à `git`, `docker`, `npm`.

### `cmd_init` — détail d'implémentation

`cmd_init` est une sous-commande de `wks`, intégrée dans le même fichier. Elle partage les couleurs, `die()`, `log()`, `warn()` déjà définis en haut du script.

**Interface :**
```
wks init [git-url] [options]

Arguments:
  git-url              URL SSH du repo (ex: git@github.com:user/repo.git)
                       Si omis → mode interactif avec prompts

Options:
  -n, --name NAME      Nom du projet (dossier dans /workspace). Défaut: basename de l'URL sans .git
  -t, --template TYPE  Template: node, php, default. Défaut: auto-detect
  -s, --subfolder PATH Sous-dossier dans le repo pour le .devcontainer. Défaut: . (racine)
  --no-up              Ne pas lancer devcontainer up après le clone
  --no-template        Ne pas appliquer de template même si pas de .devcontainer
  -h, --help           Afficher l'aide de init
```

**Auto-detect template (par ordre de priorité, après le clone) :**
| Fichier détecté | Template appliqué |
|---|---|
| `package.json` | `node` |
| `composer.json` | `php` |
| `go.mod` | `default` (pas de template go en Phase 1) |
| `Cargo.toml` | `default` (pas de template rust en Phase 1) |
| `requirements.txt` ou `pyproject.toml` | `default` (pas de template python en Phase 1) |
| Aucun | `default` |

**Mode interactif** (déclenché si `wks init` sans argument) :
```
Git URL: <saisie>
Project name [<déduit de l'URL>]: <saisie optionnelle>
Subfolder [.]: <saisie optionnelle>
  → après le clone, auto-detect du template
Template [<auto-détecté>]: <saisie optionnelle>
```

```bash
# ── cmd_init ──────────────────────────────────────────────────────────────────
# Intégré dans scripts/wks, partage les variables et fonctions du script parent.
# Placé avant cmd_open dans le fichier pour ordre logique.
cmd_init() {
    local git_url=""
    local project_name=""
    local template_type=""
    local subfolder="."
    local do_up=true
    local do_template=true
    local interactive=false

    # ── Parse args ────────────────────────────────────────────────────────────
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                echo ""
                echo -e "${CYAN}wks init${NC} — Bootstrap a new project"
                echo ""
                echo -e "Usage: wks init [git-url] [options]"
                echo ""
                echo -e "Options:"
                echo -e "  -n, --name NAME      Project name (default: derived from URL)"
                echo -e "  -t, --template TYPE  Template: node, php, default (default: auto-detect)"
                echo -e "  -s, --subfolder PATH Subfolder in repo for devcontainer (default: .)"
                echo -e "  --no-up              Skip devcontainer up"
                echo -e "  --no-template        Skip template application"
                echo -e "  -h, --help           Show this help"
                echo ""
                return 0
                ;;
            -n|--name)      project_name="$2"; shift 2 ;;
            -t|--template)  template_type="$2"; shift 2 ;;
            -s|--subfolder) subfolder="$2"; shift 2 ;;
            --no-up)        do_up=false; shift ;;
            --no-template)  do_template=false; shift ;;
            -*)             die "Unknown option: $1. Run: wks init --help" ;;
            *)
                if [ -z "$git_url" ]; then
                    git_url="$1"
                else
                    die "Unexpected argument: $1"
                fi
                shift
                ;;
        esac
    done

    # ── Mode interactif si pas d'URL ──────────────────────────────────────────
    if [ -z "$git_url" ]; then
        interactive=true
        echo ""
        echo -e "${CYAN}wks init — interactive mode${NC}"
        echo ""
        read -rp "Git URL: " git_url
        [ -z "$git_url" ] && die "Git URL is required."

        local default_name
        default_name=$(basename "$git_url" .git)
        read -rp "Project name [$default_name]: " input_name
        project_name="${input_name:-$default_name}"

        read -rp "Subfolder [.]: " input_subfolder
        subfolder="${input_subfolder:-.}"
    fi

    # ── Dériver le nom si non fourni ──────────────────────────────────────────
    [ -z "$project_name" ] && project_name=$(basename "$git_url" .git)

    local target_dir="${WORKSPACE}/${project_name}"
    local workspace_path="$target_dir"
    [ "$subfolder" != "." ] && workspace_path="${target_dir}/${subfolder}"

    # ── Affichage du plan ─────────────────────────────────────────────────────
    echo ""
    info "Project:   ${project_name}"
    info "URL:       ${git_url}"
    info "Path:      ${workspace_path}"
    info "Template:  ${template_type:-auto-detect}"
    info "Dev up:    ${do_up}"
    echo ""

    # ── [1/3] Vérification SSH ────────────────────────────────────────────────
    if [[ "$git_url" =~ ^git@ ]]; then
        if ! ssh-add -l > /dev/null 2>&1; then
            warn "SSH agent has no loaded keys. Clone may fail for private repos."
            warn "Ensure SSH_AUTH_SOCK is set and ssh-add has been run on the host."
        fi
    fi

    # ── [2/3] Clone ───────────────────────────────────────────────────────────
    info "[1/3] Clone..."
    if [ -d "${target_dir}/.git" ]; then
        info "  Repository already exists at ${target_dir}."
        if [ "$interactive" = true ]; then
            read -rp "  Pull latest? [y/N]: " do_pull
            if [[ "$do_pull" =~ ^[yY]$ ]]; then
                git -C "$target_dir" pull --rebase
                info "  Pulled."
            fi
        else
            info "  Skipping (already exists). Pull manually if needed."
        fi
    else
        git clone "$git_url" "$target_dir"
        info "  Cloned to ${target_dir}."
    fi

    # ── [3/3] Template ────────────────────────────────────────────────────────
    info "[2/3] Template..."
    if [ "$do_template" = false ]; then
        info "  Skipped (--no-template)."
    elif [ -d "${workspace_path}/.devcontainer" ]; then
        info "  .devcontainer already exists — skipped."
    else
        # Auto-detect après le clone (code source présent)
        if [ -z "$template_type" ]; then
            if   [ -f "${workspace_path}/package.json" ];  then template_type="node"
            elif [ -f "${workspace_path}/composer.json" ]; then template_type="php"
            else                                                template_type="default"
            fi
            info "  Auto-detected template: ${template_type}"
        fi

        # Mode interactif : proposer de changer
        if [ "$interactive" = true ]; then
            read -rp "  Template [$template_type]: " input_template
            template_type="${input_template:-$template_type}"
        fi

        local template_src="${TEMPLATES_DIR}/${template_type}"
        if [ ! -d "$template_src" ]; then
            warn "  Template '${template_type}' not found. Falling back to 'default'."
            template_type="default"
            template_src="${TEMPLATES_DIR}/default"
        fi

        mkdir -p "$workspace_path"
        cp -r "${template_src}/.devcontainer" "${workspace_path}/"
        info "  Template '${template_type}' applied."
    fi

    # ── [3/3] devcontainer up ─────────────────────────────────────────────────
    info "[3/3] devcontainer up..."
    if [ "$do_up" = false ]; then
        info "  Skipped (--no-up). Start later with: wks open ${project_name}"
    else
        devcontainer up --workspace-folder "$workspace_path"
        info "  Devcontainer started."
    fi

    # ── Résumé ────────────────────────────────────────────────────────────────
    echo ""
    echo -e "${GREEN}✓ Project '${project_name}' initialized.${NC}"
    echo ""
    echo -e "  ${CYAN}wks open${NC}   ${project_name}"
    echo -e "  ${CYAN}wks exec${NC}   ${project_name}"
    echo -e "  ${CYAN}wks status${NC}"
    echo ""
}
```

**Notes :**
- `cmd_init` utilise des variables **locales** (`local git_url`, etc.) — pas de pollution du scope global du script `wks`.
- Le `WORKSPACE` et `TEMPLATES_DIR` sont des variables globales définies en haut de `wks`, réutilisées ici.
- L'auto-detect template se fait APRÈS le clone — le code source est nécessaire pour inspecter `package.json` etc.
- `WORKSPACE_PATH` est normalisé : si `subfolder=.`, on garde `target_dir` directement (évite `/workspace/proj/.`).
- En mode interactif, le prompt template est posé APRÈS le clone et l'auto-detect — l'utilisateur voit la suggestion avant de valider.

---

### `templates/node/`

**Structure :**
```
templates/node/.devcontainer/
├── devcontainer.json
├── Dockerfile
└── scripts/
    └── post-create.sh
```

**`devcontainer.json` :**
```json
{
    "name": "Node.js Environment",
    "build": {
        "dockerfile": "Dockerfile"
    },
    "customizations": {
        "vscode": {
            "extensions": [
                "dbaeumer.vscode-eslint"
            ]
        }
    },
    "postCreateCommand": "bash .devcontainer/scripts/post-create.sh",
    "remoteUser": "node"
}
```

**`Dockerfile` :**
```dockerfile
ARG NODE_VERSION=22
FROM mcr.microsoft.com/devcontainers/javascript-node:${NODE_VERSION}-bullseye

# Installer safe-npm globalement
RUN npm install -g @dendronhq/safe-npm

# Remplacer npm par safe-npm via symlink
# ln -sf écrase le lien existant sans erreur
# safe-npm est dans $(npm root -g)/../bin/safe-npm après npm install -g
RUN ln -sf "$(which safe-npm)" /usr/local/bin/npm

# Vérification que le wrapper est en place
RUN npm --version
```

**`scripts/post-create.sh` :**
```bash
#!/bin/bash
set -euo pipefail

echo "[post-create] Running safe-npm install..."
# npm est maintenant safe-npm via le symlink dans le Dockerfile
npm install

echo "[post-create] Done."
```

**Notes :**
- `postCreateCommand` référence le script par son chemin relatif au workspace-folder. Le `.devcontainer/scripts/` est dans le repo après le `cp -r` du template.
- `ln -sf $(which safe-npm)` est évalué au build de l'image devcontainer — `which safe-npm` retourne le chemin absolu du binaire installé.
- La vérification `npm --version` dans le Dockerfile confirme que le symlink est fonctionnel dès le build.
- `remoteUser: node` correspond à l'utilisateur non-root de l'image `javascript-node`.

---

### `templates/php/`

**Structure :**
```
templates/php/.devcontainer/
├── devcontainer.json
├── Dockerfile
└── scripts/
    └── post-create.sh
```

**`devcontainer.json` :**
```json
{
    "name": "PHP Environment",
    "build": {
        "dockerfile": "Dockerfile"
    },
    "customizations": {
        "vscode": {
            "extensions": [
                "xdebug.php-debug",
                "bmewburn.vscode-intelephense-client"
            ]
        }
    },
    "forwardPorts": [8080],
    "postCreateCommand": "bash .devcontainer/scripts/post-create.sh",
    "remoteUser": "vscode"
}
```

**`Dockerfile` :**
```dockerfile
ARG PHP_VERSION=8
FROM mcr.microsoft.com/devcontainers/php:${PHP_VERSION}-bullseye
```

**`scripts/post-create.sh` :**
```bash
#!/bin/bash
set -euo pipefail

echo "[post-create] Checking Composer dependencies..."
if [ -f composer.json ]; then
    composer install --no-interaction
    echo "[post-create] Composer install done."
else
    echo "[post-create] No composer.json found — skipping."
fi
```

---

### `templates/default/`

**Structure :**
```
templates/default/.devcontainer/
├── devcontainer.json
└── Dockerfile
```

**`devcontainer.json` :**
```json
{
    "name": "Default Environment",
    "build": {
        "dockerfile": "Dockerfile"
    },
    "remoteUser": "vscode"
}
```

**`Dockerfile` :**
```dockerfile
FROM mcr.microsoft.com/devcontainers/base:debian
```

**Notes :**
- Pas de `postCreateCommand` pour le template default — aucune dépendance à installer.
- Le Dockerfile est minimal mais présent pour cohérence structurelle avec node et php.

---

### `.env.sample`

```bash
# ─── API ─────────────────────────────────────────────────────────────────────
ANTHROPIC_API_KEY=todo-put-your-apikey-here

# ─── Git Identity ─────────────────────────────────────────────────────────────
GIT_AUTHOR_NAME="Your Name"
GIT_AUTHOR_EMAIL="your.email@example.com"

# ─── SSH Agent (required for private repos) ───────────────────────────────────
# Find your socket path:
#   Linux : echo $SSH_AUTH_SOCK
#   macOS : echo $SSH_AUTH_SOCK
# Verify keys are loaded: ssh-add -l
SSH_AUTH_SOCK=/run/user/1000/ssh-agent.socket

# ─── Workstation image versions (optional) ────────────────────────────────────
# NODE_VERSION=22
# DEVCONTAINER_CLI_VERSION=0.75.0

# ─── Port forwarding (optional) ───────────────────────────────────────────────
# Single port pair. For multiple ports, use compose.override.yaml:
#   services:
#     workstation:
#       ports:
#         - "5173:5173"
#         - "8080:8080"
# FORWARD_PORT=5173
```

**Variables supprimées vs l'existant :** `GIT_URL`, `REPO_NAME`, `SUBFOLDER`, `TEMPLATE_TYPE`.

---

### `.gitignore`

Ajouter `.local/plan/` comme exception explicite si on veut versionner les plans futurs (actuellement `*.local` les ignore). Pour l'instant, les plans restent dans `.local/` (gitignored) — le plan consolidé est dans `aidd_docs/` (versionné).

**Changement à faire :**
```
# Ajouter après la ligne *.local :
!aidd_docs/
```

`aidd_docs/` doit être suivi par git. Vérifier que `*.local` n'ignore pas `aidd_docs/` (il ne le fait pas — `*.local` correspond aux fichiers/dossiers se terminant par `.local`, pas aux dossiers standard).

**Aucun changement nécessaire au `.gitignore`** — `aidd_docs/` n'est pas ignoré par les règles existantes.

---

### `AGENTS.md`

Sections à mettre à jour :

1. **"What this repo is"** : mentionner workstation multi-projets
2. **"Running the project"** : remplacer le workflow mono-projet par `wks init` + `wks open`
3. **"Required `.env` values"** : supprimer GIT_URL/REPO_NAME/SUBFOLDER/TEMPLATE_TYPE, ajouter NODE_VERSION/DEVCONTAINER_CLI_VERSION/FORWARD_PORT
4. **"Architecture notes"** :
   - `dev` → `workstation`
   - TLS activé (port 2376)
   - `bootstrap.sh` → `scripts/entrypoint.sh`
   - Port 5173 plus hardcodé
   - safe-npm via symlink dans le Dockerfile du template (fonctionne dans les scripts)
   - `workspace/` monté dans workstation + daemon
5. **"Devcontainer templates"** : mentionner que chaque template a maintenant un Dockerfile + post-create.sh

---

## Ordre d'implémentation recommandé

L'ordre suivant minimise les allers-retours et permet de tester à chaque étape :

```
1. compose.yaml          → base pour tout le reste
2. Dockerfile            → image buildable
3. scripts/entrypoint.sh → container démarre avec wks disponible
4. scripts/wks           → interface principale + wks init intégré (7 commandes)
5. templates/node/       → template enrichi le plus utilisé
7. templates/php/        → idem
8. templates/default/    → idem
9. .env.sample           → doc utilisateur
10. AGENTS.md            → doc interne
10. Supprimer bootstrap.sh
```

**Gate de validation entre chaque étape :** `docker compose up --build` doit réussir à chaque étape pour éviter l'accumulation de dettes de debug.

---

## Points d'attention à l'implémentation

1. **`devcontainer down`** — vérifier que la commande existe dans la version de `@devcontainers/cli` choisie. Dans certaines versions, c'est `devcontainer stop` ou il faut passer par `docker rm`. À valider au moment de fixer `DEVCONTAINER_CLI_VERSION`.

2. **Label `devcontainer.local_folder`** — ce label est posé par le devcontainer CLI sur le container créé. Vérifier le nom exact du label sur la version installée avec `docker inspect <container> | grep -i devcontainer`. Le nom peut varier selon la version.

3. **`opencode --cwd`** — vérifier que le flag `--cwd` est supporté par la version d'opencode installée. Alternative : `cd <workdir> && opencode` si `--cwd` n'existe pas.

4. **Permissions sur `/workspace`** — les fichiers clonés par le workstation (root) dans `/workspace/` doivent être lisibles par le devcontainer (user `node` ou `vscode`). Le `git config --global --add safe.directory "*"` dans l'entrypoint couvre git, mais les permissions filesystem peuvent poser problème. À tester.

5. **`DOCKER_TLS_CERTDIR` et le volume `certs-client`** — le daemon écrit dans `/certs/client/` du volume. Le workstation monte ce même volume en `:ro`. La synchronisation est assurée par Docker (les writes du daemon sont visibles immédiatement par le workstation via le named volume). Pas de race condition théorique, mais le wait loop dans `entrypoint.sh` couvre le cas où les certs ne sont pas encore générés.

6. **`bash-completion`** — pour que tab-complete fonctionne sur `wks`, ajouter un fichier de complétion dans `/etc/bash_completion.d/wks` est une amélioration Phase 2.

7. **`scripts/` dans le repo vs symlinks** — le `chmod +x` sur les scripts dans `entrypoint.sh` (`chmod +x "$script"`) modifie les permissions du fichier sur le bind mount, donc sur l'hôte. C'est intentionnel (les scripts doivent être exécutables), mais à noter.
