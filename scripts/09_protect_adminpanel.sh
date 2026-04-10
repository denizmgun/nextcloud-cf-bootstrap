#!/usr/bin/env bash
# 09_protect_adminpanel.sh — Verify Cloudflare Access is protecting the admin panel.
#
# Cloudflare Access intercepts requests at the edge before routing to the origin,
# so this check is valid even before Nextcloud is running: a protected hostname
# returns a CF Access redirect (302 → cloudflareaccess.com); an unprotected one
# returns a tunnel error (502) or no response at all.
#
# Exits 0 in all cases — this is a soft gate, not a hard block.
# The caller decides whether to proceed if the user skips protection.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"

ADMIN_HOSTNAME=""
if [[ -f "$ENV_FILE" ]]; then
    ADMIN_HOSTNAME="$(grep "^ADMIN_HOSTNAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)" || true
fi

if [[ -z "$ADMIN_HOSTNAME" ]]; then
    log_warn "ADMIN_HOSTNAME not set — skipping Cloudflare Access check."
    exit 0
fi

# ── Detection ─────────────────────────────────────────────────────────────────
_cf_access_active() {
    local location
    location="$(curl -sI --max-time 10 "https://${ADMIN_HOSTNAME}" 2>/dev/null \
        | grep -i '^location:' | tr -d '\r' | awk '{print $2}')"
    echo "$location" | grep -qi "cloudflareaccess\.com"
}

# ── Check loop ────────────────────────────────────────────────────────────────
echo ""
log_info "Checking whether Cloudflare Access is protecting https://${ADMIN_HOSTNAME}..."

while true; do
    if _cf_access_active; then
        log_info "Cloudflare Access confirmed on ${ADMIN_HOSTNAME}."
        exit 0
    fi

    echo ""
    log_warn "Cloudflare Access was NOT detected on https://${ADMIN_HOSTNAME}."
    log_warn "Once Nextcloud starts, the admin panel will be reachable without an identity gate."
    echo ""
    echo "  You can set it up now — it only takes a minute:"
    echo ""
    echo "    1. Open https://one.dash.cloudflare.com"
    echo "       Go to: Access > Applications > Add an application > Self-hosted"
    echo "    2. Application domain: ${ADMIN_HOSTNAME}"
    echo "    3. Policy action: Allow — add your email (or choose One-time PIN)"
    echo "    4. Save the application."
    echo ""
    echo "  Then come back here and select 'Check again'."
    echo ""

    ACTION=""
    prompt_yes_no ACTION "Check again? (No = proceed without Cloudflare Access protection)"

    if [[ "$ACTION" == "yes" ]]; then
        log_info "Re-checking..."
        continue
    fi

    echo ""
    log_warn "Proceeding without Cloudflare Access."
    log_warn "The admin panel will be protected only by the AIO passphrase until Access is added."
    exit 0
done
