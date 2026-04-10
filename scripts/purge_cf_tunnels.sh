#!/usr/bin/env bash
# purge_cf_tunnels.sh — Delete all named Cloudflare Tunnels on the authenticated account.
#
# Run this before 05_configure_tunnel.sh if a previous tunnel exists on another
# machine, to prevent stale connectors from splitting traffic to the old host.
#
# NOTE: DNS CNAME records created by cloudflared are NOT automatically removed.
#       Delete them manually in the Cloudflare DNS dashboard if needed.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

check_root

log_info "Cloudflare Tunnel purge utility"

if ! command_exists cloudflared; then
    log_error "cloudflared is not installed. Run script 02 first."
    exit 1
fi

# ── Authenticate if needed ────────────────────────────────────────────────────
CF_CERT="${HOME}/.cloudflared/cert.pem"
if [[ ! -f "$CF_CERT" ]]; then
    log_warn "No Cloudflare credentials found. Starting login..."
    echo ""
    cloudflared tunnel login
fi

# ── List tunnels ──────────────────────────────────────────────────────────────
log_info "Fetching tunnel list..."
TUNNEL_JSON="$(cloudflared tunnel list --output json 2>/dev/null || echo '[]')"
TUNNEL_COUNT="$(echo "$TUNNEL_JSON" \
    | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)"

if [[ "$TUNNEL_COUNT" -eq 0 ]]; then
    log_info "No tunnels found on this account. Nothing to purge."
    exit 0
fi

echo ""
log_warn "The following tunnel(s) will be permanently deleted:"
echo "$TUNNEL_JSON" | python3 -c "
import sys, json
for t in json.load(sys.stdin):
    print(f\"  {t['id']}  {t['name']}\")
"
echo ""
log_warn "This action is irreversible."
log_warn "DNS CNAME records created by these tunnels will NOT be removed automatically."
echo ""

CONFIRM=""
prompt_yes_no CONFIRM "Permanently delete all ${TUNNEL_COUNT} tunnel(s) listed above?"
if [[ "$CONFIRM" != "yes" ]]; then
    log_info "Aborted. No tunnels were deleted."
    exit 0
fi

# ── Delete each tunnel ────────────────────────────────────────────────────────
TUNNEL_NAMES="$(echo "$TUNNEL_JSON" \
    | python3 -c "import sys,json; [print(t['name']) for t in json.load(sys.stdin)]")"

while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    log_info "Cleaning up active connections for '${name}'..."
    cloudflared tunnel cleanup "$name" 2>/dev/null || true
    log_info "Deleting tunnel '${name}'..."
    cloudflared tunnel delete --force "$name"
    log_info "Deleted '${name}'."
done <<< "$TUNNEL_NAMES"

echo ""
log_info "All tunnels deleted."
log_warn "Reminder: DNS CNAME records for these tunnels still exist in Cloudflare."
log_warn "Remove them at: https://dash.cloudflare.com → your domain → DNS → Records"
