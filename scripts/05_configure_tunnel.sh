#!/usr/bin/env bash
# 05_configure_tunnel.sh — Collect Cloudflare Tunnel credentials and write config.
# The tunnel token is stored ONLY in ~/.cloudflared/.env (mode 600).
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"
CF_DIR="${HOME}/.cloudflared"
CF_ENV_FILE="${CF_DIR}/.env"
CF_CONFIG="${CF_DIR}/config.yml"

log_info "Step 05: Configure Cloudflare Tunnel"

# ── Prerequisite ──────────────────────────────────────────────────────────────
if ! command_exists cloudflared; then
    log_error "cloudflared is not installed. Run script 02 first."
    exit 1
fi

# ── Idempotency ───────────────────────────────────────────────────────────────
if [[ -f "$CF_CONFIG" ]]; then
    OVERWRITE=""
    prompt_yes_no OVERWRITE \
        "Tunnel config already exists at ${CF_CONFIG}. Overwrite?"
    if [[ "$OVERWRITE" != "yes" ]]; then
        log_info "Keeping existing tunnel config."
        exit 0
    fi
fi

# ── Prompts ───────────────────────────────────────────────────────────────────
echo ""
echo "You need the Tunnel token from: Cloudflare Zero Trust > Networks > Tunnels"
echo "Create or select a tunnel, then copy the token shown in the 'Install connector' step."
echo ""

CLOUDFLARE_TUNNEL_TOKEN=""
NC_HOSTNAME=""
ADMIN_HOSTNAME=""

prompt_required CLOUDFLARE_TUNNEL_TOKEN \
    "Cloudflare Tunnel token"
prompt_required NC_HOSTNAME \
    "Public hostname for Nextcloud (e.g. nextcloud.example.com)"
prompt_required ADMIN_HOSTNAME \
    "Public hostname for AIO admin panel (e.g. nextcloud-admin.example.com)"

# ── Extract Tunnel ID from JWT ────────────────────────────────────────────────
# The token is a JWT; field "t" in the payload holds the Tunnel UUID.
TUNNEL_ID=""
if command_exists python3; then
    TUNNEL_ID="$(echo "$CLOUDFLARE_TUNNEL_TOKEN" \
        | cut -d. -f2 \
        | base64 --decode 2>/dev/null \
        | python3 -c "import sys, json; print(json.load(sys.stdin).get('t',''))" 2>/dev/null \
        || true)"
fi

if [[ -z "$TUNNEL_ID" ]]; then
    log_warn "Could not extract Tunnel ID automatically from token."
    prompt_required TUNNEL_ID \
        "Enter your Tunnel ID (UUID shown in the Zero Trust dashboard)"
fi

log_info "Tunnel ID: ${TUNNEL_ID}"

# ── Write config files ────────────────────────────────────────────────────────
mkdir -p "$CF_DIR"
chmod 700 "$CF_DIR"

TEMPLATE="${SCRIPT_DIR}/templates/config.yml.tpl"
if [[ ! -f "$TEMPLATE" ]]; then
    log_error "Template not found: ${TEMPLATE}"
    exit 1
fi

sed \
    -e "s|{{TUNNEL_ID}}|${TUNNEL_ID}|g" \
    -e "s|{{ADMIN_HOSTNAME}}|${ADMIN_HOSTNAME}|g" \
    -e "s|{{NC_HOSTNAME}}|${NC_HOSTNAME}|g" \
    "$TEMPLATE" > "$CF_CONFIG"
chmod 600 "$CF_CONFIG"
log_info "Wrote tunnel config to ${CF_CONFIG}"

# Store token in its own restricted file — NEVER write to the shared .env
printf 'CLOUDFLARE_TUNNEL_TOKEN=%s\n' "$CLOUDFLARE_TUNNEL_TOKEN" > "$CF_ENV_FILE"
chmod 600 "$CF_ENV_FILE"
log_info "Tunnel token stored in ${CF_ENV_FILE} (mode 600)"

# Write non-secret values to shared .env
env_set "NC_HOSTNAME"    "$NC_HOSTNAME"    "$ENV_FILE"
env_set "ADMIN_HOSTNAME" "$ADMIN_HOSTNAME" "$ENV_FILE"
env_set "TUNNEL_ID"      "$TUNNEL_ID"      "$ENV_FILE"

log_info "Tunnel configuration complete."
