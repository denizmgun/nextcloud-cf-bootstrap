#!/usr/bin/env bash
# 04_install_rclone.sh — Install rclone via the official install script.
# Only runs when RCLONE_ENABLED=yes in ~/.nextcloud/.env.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"

# ── Guard ─────────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]] && grep -q "^RCLONE_ENABLED=no$" "$ENV_FILE"; then
    log_info "RCLONE_ENABLED is 'no'. Skipping rclone installation."
    exit 0
fi

log_info "Step 04: Install rclone"

# ── Idempotency ───────────────────────────────────────────────────────────────
if command_exists rclone; then
    log_info "rclone is already installed. Skipping."
    rclone version
    exit 0
fi

# ── Install ───────────────────────────────────────────────────────────────────
log_info "Downloading and running the official rclone install script..."
curl -fsSL --retry 3 https://rclone.org/install.sh | bash

log_info "Installing FUSE3 (required for rclone mount)..."
apt-get install -y fuse3

# ── Validate ──────────────────────────────────────────────────────────────────
log_info "Validating rclone installation..."
rclone version
log_info "rclone installed successfully."
