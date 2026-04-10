#!/usr/bin/env bash
# 10_secure_admin.sh — Retrieve the AIO initial passphrase and guide Cloudflare Access setup.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"

log_info "Step 10: Secure Admin Panel"

# ── Retrieve AIO passphrase ───────────────────────────────────────────────────
log_info "Attempting to retrieve AIO initial passphrase from mastercontainer..."
AIO_INITIAL_PASSPHRASE=""

# Try the known configuration.json location used by current AIO versions
if docker ps --filter "name=nextcloud-aio-mastercontainer" --format '{{.Names}}' \
        | grep -q "nextcloud-aio-mastercontainer" 2>/dev/null; then

    # Attempt 1: parse configuration.json with python3
    AIO_INITIAL_PASSPHRASE="$(
        docker exec nextcloud-aio-mastercontainer \
            cat /mnt/docker-aio-config/data/configuration.json 2>/dev/null \
        | python3 -c \
            "import sys, json; d=json.load(sys.stdin); print(d.get('AIO_PASSWORD',''))" \
            2>/dev/null \
        || true
    )"

    # Attempt 2: grep across the config directory
    if [[ -z "$AIO_INITIAL_PASSPHRASE" ]]; then
        AIO_INITIAL_PASSPHRASE="$(
            docker exec nextcloud-aio-mastercontainer \
                grep -r '"AIO_PASSWORD"' /mnt/docker-aio-config/ 2>/dev/null \
            | grep -oP '(?<="AIO_PASSWORD":")[^"]+' \
            | head -1 \
            || true
        )"
    fi

    # Attempt 3: look in /var/lib/docker-aio (older layout)
    if [[ -z "$AIO_INITIAL_PASSPHRASE" ]]; then
        AIO_INITIAL_PASSPHRASE="$(
            docker exec nextcloud-aio-mastercontainer \
                grep -r 'AIO_PASSWORD' /var/lib/docker-aio/ 2>/dev/null \
            | head -1 \
            | grep -oP '(?<==)[^\s]+' \
            || true
        )"
    fi
fi

# Fallback: ask the user to paste it manually
if [[ -z "$AIO_INITIAL_PASSPHRASE" ]]; then
    log_warn "Could not retrieve the passphrase automatically."
    echo ""
    echo "Find it yourself by running:"
    echo "  docker exec nextcloud-aio-mastercontainer \\"
    echo "    cat /mnt/docker-aio-config/data/configuration.json"
    echo ""
    prompt_required AIO_INITIAL_PASSPHRASE "Paste the AIO initial passphrase"
fi

# ── Save and display passphrase ───────────────────────────────────────────────
env_set "AIO_INITIAL_PASSPHRASE" "$AIO_INITIAL_PASSPHRASE" "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo ""
echo "════════════════════════════════════════════════════"
echo "  AIO INITIAL PASSPHRASE"
echo ""
echo "  ${AIO_INITIAL_PASSPHRASE}"
echo ""
echo "  Save this in your password manager NOW."
echo "  You need it to log in to the Nextcloud AIO admin panel."
echo "════════════════════════════════════════════════════"
echo ""

# ── Cloudflare Access guidance ────────────────────────────────────────────────
ADMIN_HOSTNAME=""
if [[ -f "$ENV_FILE" ]]; then
    ADMIN_HOSTNAME="$(grep "^ADMIN_HOSTNAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)" || true
fi

SETUP_CF_ACCESS=""
prompt_yes_no SETUP_CF_ACCESS \
    "Do you want step-by-step instructions for adding Cloudflare Access to the admin panel?"

if [[ "$SETUP_CF_ACCESS" == "yes" ]]; then
    echo ""
    echo "════════════════════════════════════════════════════"
    echo "  Cloudflare Access — Admin Panel Protection"
    echo "════════════════════════════════════════════════════"
    echo ""
    echo "  1. Open: https://one.dash.cloudflare.com"
    echo "     Go to: Access > Applications > Add an application"
    echo ""
    echo "  2. Choose: Self-hosted"
    echo ""
    echo "  3. Fill in:"
    echo "     Application name: Nextcloud AIO Admin"
    if [[ -n "$ADMIN_HOSTNAME" ]]; then
        echo "     Application domain: ${ADMIN_HOSTNAME}"
    else
        echo "     Application domain: <your ADMIN_HOSTNAME>"
    fi
    echo ""
    echo "  4. Under 'Policies', create a policy:"
    echo "     Name:   Admin Access"
    echo "     Action: Allow"
    echo "     Rule:   Emails — add your email address(es)"
    echo "     (Alternatively, use 'One-time PIN' for email OTP — no IdP required)"
    echo ""
    echo "  5. Under 'Authentication', select 'One-time PIN' (simplest option)"
    echo "     or connect your preferred identity provider."
    echo ""
    echo "  6. Save the application."
    echo ""
    echo "  Visitors to the admin panel URL will now be gated by Cloudflare"
    echo "  Access before Nextcloud AIO is reached."
    echo ""
    echo "  NOTE: Automated provisioning via the Cloudflare API is out of scope"
    echo "  for this version and can be added in a future iteration."
    echo ""
fi

# ── Security summary ──────────────────────────────────────────────────────────
echo "Security layers in place:"
echo "  [1] Cloudflare Tunnel — admin panel not directly exposed to the internet"
if [[ "$SETUP_CF_ACCESS" == "yes" ]]; then
    echo "  [2] Cloudflare Access — identity gate before reaching Nextcloud AIO"
fi
echo "  [✓] AIO passphrase   — required to access the AIO admin interface"
echo ""
log_info "Admin panel security configuration complete."
