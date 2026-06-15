#!/bin/bash
set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

log()      { echo -e "${GREEN}[workstation]${NC} $1"; }
warn()     { echo -e "${YELLOW}[workstation]${NC} $1"; }
err()      { echo -e "${RED}[workstation]${NC} $1" >&2; }
# exit 1 — user/config error  |  exit 2 — system error (daemon, TLS, infra)
die_user() { err "$1"; exit 1; }
die_sys()  { err "System error: $1"; exit 2; }

# ── Symlinks scripts → PATH ───────────────────────────────────────────────────
# /workspace_root is the bind mount of . (repo root).
# Scripts are editable from the host and accessible in PATH via symlinks.
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

# ── Git identity ──────────────────────────────────────────────────────────────
git config --global --add safe.directory "*" 2>/dev/null || true
[ -n "${GIT_AUTHOR_NAME:-}"  ] && git config --global user.name  "$GIT_AUTHOR_NAME"
[ -n "${GIT_AUTHOR_EMAIL:-}" ] && git config --global user.email "$GIT_AUTHOR_EMAIL"

# ── SSH agent check ───────────────────────────────────────────────────────────
if [ ! -S "/tmp/ssh-agent.sock" ]; then
    warn "SSH agent socket not available at /tmp/ssh-agent.sock"
    warn "Private repos will fail. Ensure SSH_AUTH_SOCK is set in .env"
    warn "Public repos via HTTPS are unaffected."
fi

# ── Wait for TLS certificates ─────────────────────────────────────────────────
# docker:dind generates certs in /certs/client/ on startup.
# Wait until all three files are present before attempting any Docker connection.
TLS_CERT_PATH="${DOCKER_CERT_PATH:-/certs/client}"
if [ "${DOCKER_TLS_VERIFY:-0}" = "1" ]; then
    log "Waiting for TLS certificates at $TLS_CERT_PATH ..."
    MAX_TLS_WAIT=30
    elapsed=0
    until [ -f "${TLS_CERT_PATH}/ca.pem" ] && [ -f "${TLS_CERT_PATH}/cert.pem" ] && [ -f "${TLS_CERT_PATH}/key.pem" ]; do
        if [ $elapsed -ge $MAX_TLS_WAIT ]; then
            die_sys "TLS certificates not available after ${MAX_TLS_WAIT}s. Check daemon logs."
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    log "TLS certificates ready."
fi

# ── Wait for Docker daemon ────────────────────────────────────────────────────
# The compose healthcheck (service_healthy) should guarantee the daemon is up
# before this container starts, but we keep a local check as a safety net.
log "Verifying Docker daemon connection..."
MAX_DOCKER_WAIT=30
elapsed=0
until docker info > /dev/null 2>&1; do
    if [ $elapsed -ge $MAX_DOCKER_WAIT ]; then
        die_sys "Docker daemon not reachable after ${MAX_DOCKER_WAIT}s. DOCKER_HOST=${DOCKER_HOST:-not set}"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
log "Docker daemon ready. (${DOCKER_HOST})"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}  Workstation ready.${NC}"
echo -e "  ${GREEN}wks init${NC}          Bootstrap a new project"
echo -e "  ${GREEN}wks help${NC}          Manage running projects"
echo ""

# ── Idle ──────────────────────────────────────────────────────────────────────
exec tail -f /dev/null
