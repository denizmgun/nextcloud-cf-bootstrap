#!/usr/bin/env bash
# 08_connect_tunnel.sh — Install cloudflared as a systemd service and verify the tunnel is live.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"
CF_ENV_FILE="${HOME}/.cloudflared/.env"
CF_CONFIG="${HOME}/.cloudflared/config.yml"

MAX_RETRIES=5
RETRY_INTERVAL=5

log_info "Step 08: Connect Cloudflare Tunnel"

# ── Prerequisites ─────────────────────────────────────────────────────────────
if [[ ! -f "$CF_CONFIG" ]]; then
    log_error "Tunnel config not found at ${CF_CONFIG}. Run script 05 first."
    exit 1
fi
if [[ ! -f "$CF_ENV_FILE" ]]; then
    log_error "Tunnel token file not found at ${CF_ENV_FILE}. Run script 05 first."
    exit 1
fi

# shellcheck source=/dev/null
source "$CF_ENV_FILE"
if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
    log_error "CLOUDFLARE_TUNNEL_TOKEN is not set in ${CF_ENV_FILE}."
    exit 1
fi

# ── Install as systemd service ────────────────────────────────────────────────
log_info "Installing cloudflared as a systemd service..."
cloudflared service install "$CLOUDFLARE_TUNNEL_TOKEN"

log_info "Enabling and starting cloudflared..."
systemctl enable --now cloudflared

# ── Poll for service health ───────────────────────────────────────────────────
log_info "Waiting for cloudflared service to become active (up to $((MAX_RETRIES * RETRY_INTERVAL))s)..."
TUNNEL_ACTIVE=false
for i in $(seq 1 $MAX_RETRIES); do
    if systemctl is-active --quiet cloudflared; then
        log_info "cloudflared service is active."
        TUNNEL_ACTIVE=true
        break
    fi
    log_warn "Service not yet active (attempt ${i}/${MAX_RETRIES}). Waiting ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

if ! $TUNNEL_ACTIVE; then
    log_error "cloudflared service did not become active within the timeout."
    systemctl status cloudflared --no-pager || true
    exit 1
fi

# ── External validation ───────────────────────────────────────────────────────
ADMIN_HOSTNAME=""
if [[ -f "$ENV_FILE" ]]; then
    ADMIN_HOSTNAME="$(grep "^ADMIN_HOSTNAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)" || true
fi

if [[ -n "$ADMIN_HOSTNAME" ]]; then
    log_info "Validating tunnel externally via https://${ADMIN_HOSTNAME}..."
    CURL_OK=false
    for i in $(seq 1 $MAX_RETRIES); do
        HTTP_CODE="$(curl -sk -o /dev/null -w "%{http_code}" \
            --max-time 10 \
            "https://${ADMIN_HOSTNAME}" 2>/dev/null || true)"
        # Any non-empty, non-000 response means the tunnel is routing traffic
        if [[ -n "$HTTP_CODE" && "$HTTP_CODE" != "000" ]]; then
            log_info "Tunnel is reachable (HTTP ${HTTP_CODE}). Tunnel is live."
            CURL_OK=true
            break
        fi
        log_warn "No response yet from https://${ADMIN_HOSTNAME} (attempt ${i}/${MAX_RETRIES})..."
        sleep $RETRY_INTERVAL
    done
    if ! $CURL_OK; then
        log_error "External tunnel validation failed after ${MAX_RETRIES} attempts."
        exit 1
    fi
else
    log_warn "ADMIN_HOSTNAME not set; skipping external HTTP validation."
fi

log_info "Cloudflare Tunnel connected successfully."
