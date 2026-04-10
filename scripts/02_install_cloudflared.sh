#!/usr/bin/env bash
# 02_install_cloudflared.sh — Install cloudflared from Cloudflare's GitHub releases.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

log_info "Step 02: Install cloudflared"

# ── Idempotency ───────────────────────────────────────────────────────────────
if command_exists cloudflared; then
    log_info "cloudflared is already installed. Skipping."
    cloudflared version
    exit 0
fi

# ── Architecture detection ────────────────────────────────────────────────────
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  DEB_FILE="cloudflared-linux-amd64.deb" ;;
    aarch64) DEB_FILE="cloudflared-linux-arm64.deb" ;;
    *)
        log_error "Unsupported architecture: '${ARCH}'. Only x86_64 and aarch64 are supported."
        exit 1
        ;;
esac

DOWNLOAD_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/${DEB_FILE}"

# ── Download ──────────────────────────────────────────────────────────────────
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

log_info "Downloading cloudflared (${ARCH}) from GitHub..."
curl -fsSL --retry 3 --retry-delay 5 \
    -o "${TMP_DIR}/${DEB_FILE}" \
    "$DOWNLOAD_URL"

# ── Install ───────────────────────────────────────────────────────────────────
log_info "Installing ${DEB_FILE}..."
dpkg -i "${TMP_DIR}/${DEB_FILE}"

# ── Validate ──────────────────────────────────────────────────────────────────
log_info "Validating cloudflared installation..."
cloudflared version
log_info "cloudflared installed successfully."
