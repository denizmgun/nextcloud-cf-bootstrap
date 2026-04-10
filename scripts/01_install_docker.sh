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
log_info "Updating apt package index..."
apt-get update -qq

log_info "Installing prerequisites..."
apt-get install -y ca-certificates curl gnupg

log_info "Adding Docker's official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

log_info "Adding Docker apt repository..."
# shellcheck disable=SC1091
echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -qq

log_info "Installing Docker CE packages..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# ── Service ───────────────────────────────────────────────────────────────────
log_info "Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker

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
