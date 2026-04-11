#!/usr/bin/env bash
# 05_configure_tunnel.sh — Authenticate with Cloudflare, create a named tunnel, route DNS.
# Uses: cloudflared tunnel login → tunnel create → tunnel route dns
# No manual token retrieval required.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"
CF_DIR="${HOME}/.cloudflared"
CF_CONFIG="${CF_DIR}/config.yml"
CF_CERT="${CF_DIR}/cert.pem"

log_info "Step 05: Configure Cloudflare Tunnel"

if ! command_exists cloudflared; then
    log_error "cloudflared is not installed. Run script 02 first."
    exit 1
fi

# ── Authenticate ──────────────────────────────────────────────────────────────
if [[ -f "$CF_CERT" ]]; then
    log_info "Cloudflare credentials found at ${CF_CERT}. Skipping login."
else
    echo ""
    log_info "A browser link will be printed below. Open it to authorise cloudflared."
    log_info "On a headless server: copy the URL and open it on another device."
    echo ""
    cloudflared tunnel login
fi

# cloudflared tunnel login writes cert.pem to ~/.cloudflared/ but subsequent
# commands (tunnel list, tunnel create, the systemd service) look in
# /etc/cloudflared/ when ~ resolves differently or when running as a service.
# Copying here makes the cert discoverable in all contexts from this point on.
mkdir -p /etc/cloudflared
cp "$CF_CERT" /etc/cloudflared/cert.pem
chmod 600 /etc/cloudflared/cert.pem
log_info "Staged cert.pem to /etc/cloudflared/"

# ── Check for existing tunnels ────────────────────────────────────────────────
EXISTING_JSON="$(cloudflared tunnel list --output json 2>/dev/null || echo '[]')"
EXISTING_COUNT="$(echo "$EXISTING_JSON" \
    | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)"

if [[ "$EXISTING_COUNT" -gt 0 ]]; then
    echo ""
    log_warn "${EXISTING_COUNT} existing tunnel(s) found on this Cloudflare account:"
    echo "$EXISTING_JSON" | python3 -c "
import sys, json
for t in json.load(sys.stdin):
    print(f\"  {t['id']}  {t['name']}\")
"
    echo ""
    log_warn "Stale tunnels will split traffic — requests may be routed to the old machine."
    log_warn "Run  sudo bash scripts/purge_cf_tunnels.sh  to remove them first."
    echo ""
    CONTINUE=""
    prompt_yes_no CONTINUE "Create a new tunnel alongside the existing one(s) anyway?"
    if [[ "$CONTINUE" != "yes" ]]; then
        log_info "Aborted. Run purge_cf_tunnels.sh to clean up, then re-run this script."
        exit 1
    fi
fi

# ── Create tunnel ─────────────────────────────────────────────────────────────
TUNNEL_NAME=""
prompt_optional TUNNEL_NAME \
    "Name for this tunnel (shown in the Zero Trust dashboard)" "nextcloud"

log_info "Creating tunnel '${TUNNEL_NAME}'..."
cloudflared tunnel create "$TUNNEL_NAME"

# Extract the ID of the just-created tunnel
TUNNEL_ID="$(cloudflared tunnel list --output json 2>/dev/null \
    | python3 -c "
import sys, json
tunnels = json.load(sys.stdin)
matches = [t['id'] for t in tunnels if t['name'] == '${TUNNEL_NAME}']
print(matches[0] if matches else '')
" 2>/dev/null || true)"

if [[ -z "$TUNNEL_ID" ]]; then
    log_error "Could not determine Tunnel ID for '${TUNNEL_NAME}' after creation."
    exit 1
fi
log_info "Tunnel created. ID: ${TUNNEL_ID}"

# ── Hostnames ─────────────────────────────────────────────────────────────────
NC_HOSTNAME=""
ADMIN_HOSTNAME=""
prompt_required NC_HOSTNAME \
    "Public hostname for Nextcloud (e.g. nextcloud.example.com)"
prompt_required ADMIN_HOSTNAME \
    "Public hostname for AIO admin panel (e.g. nextcloud-admin.example.com)"

# ── Route DNS ─────────────────────────────────────────────────────────────────
log_info "Routing DNS: ${NC_HOSTNAME} → ${TUNNEL_NAME}"
cloudflared tunnel route dns "$TUNNEL_NAME" "$NC_HOSTNAME"

log_info "Routing DNS: ${ADMIN_HOSTNAME} → ${TUNNEL_NAME}"
cloudflared tunnel route dns "$TUNNEL_NAME" "$ADMIN_HOSTNAME"

# ── Write config.yml ──────────────────────────────────────────────────────────
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

# Also place config in /etc/cloudflared/ — the path cloudflared service install
# hardwires into the systemd unit, and the fallback cloudflared itself searches.
cp "$CF_CONFIG" /etc/cloudflared/config.yml
chmod 600 /etc/cloudflared/config.yml
log_info "Staged config.yml to /etc/cloudflared/"

# ── Persist to .env ───────────────────────────────────────────────────────────
env_set "NC_HOSTNAME"    "$NC_HOSTNAME"    "$ENV_FILE"
env_set "ADMIN_HOSTNAME" "$ADMIN_HOSTNAME" "$ENV_FILE"
env_set "TUNNEL_ID"      "$TUNNEL_ID"      "$ENV_FILE"
env_set "TUNNEL_NAME"    "$TUNNEL_NAME"    "$ENV_FILE"

log_info "Tunnel configuration complete."
