#!/usr/bin/env bash
# 01_install_docker.sh — Install Docker CE from the official Docker repository.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"

log_info "Step 01: Install Docker"

# ── Idempotency ───────────────────────────────────────────────────────────────
if command_exists docker && systemctl is-active --quiet docker 2>/dev/null; then
    log_info "Docker is already installed and running. Skipping installation."
    DOCKER_VERSION="$(docker --version | awk '{print $3}' | tr -d ',')"
    env_set "DOCKER_VERSION" "$DOCKER_VERSION" "$ENV_FILE"
    exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────
log_info "Running the official Docker install script from get.docker.com..."
curl -fsSL https://get.docker.com | sh

# ── Non-root user ─────────────────────────────────────────────────────────────
if [[ -n "${SUDO_USER:-}" ]]; then
    log_info "Adding user '${SUDO_USER}' to the docker group..."
    usermod -aG docker "$SUDO_USER"
    log_warn "User '${SUDO_USER}' must log out and back in for docker group membership to take effect."
fi

# ── Validate ──────────────────────────────────────────────────────────────────
log_info "Validating Docker installation with hello-world..."
docker run --rm hello-world

DOCKER_VERSION="$(docker --version | awk '{print $3}' | tr -d ',')"
env_set "DOCKER_VERSION" "$DOCKER_VERSION" "$ENV_FILE"
log_info "Docker ${DOCKER_VERSION} installed successfully."
