#!/usr/bin/env bash
# 10_run_nextcloud.sh — Pull and start Nextcloud AIO via Docker Compose.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"
COMPOSE_FILE="${HOME}/.nextcloud/docker-compose.yml"

HEALTH_TIMEOUT=120
HEALTH_INTERVAL=5

log_info "Step 10: Run Nextcloud AIO"

# ── Prerequisites ─────────────────────────────────────────────────────────────
if [[ ! -f "$COMPOSE_FILE" ]]; then
    log_error "docker-compose.yml not found at ${COMPOSE_FILE}. Run script 07 first."
    exit 1
fi
if ! command_exists docker; then
    log_error "Docker is not installed. Run script 01 first."
    exit 1
fi
if ! systemctl is-active --quiet docker; then
    log_error "Docker daemon is not running."
    exit 1
fi

# ── Pull images ───────────────────────────────────────────────────────────────
log_info "Pulling Nextcloud AIO images (this may take a few minutes)..."
docker compose -f "$COMPOSE_FILE" pull

# ── Start containers ──────────────────────────────────────────────────────────
log_info "Starting Nextcloud AIO containers..."
docker compose -f "$COMPOSE_FILE" up -d

# ── Wait for mastercontainer health ──────────────────────────────────────────
log_info "Waiting for nextcloud-aio-mastercontainer to become healthy (timeout: ${HEALTH_TIMEOUT}s)..."
ELAPSED=0
while [[ $ELAPSED -lt $HEALTH_TIMEOUT ]]; do
    STATUS="$(docker inspect \
        --format='{{.State.Health.Status}}' \
        nextcloud-aio-mastercontainer 2>/dev/null || echo "not_found")"

    case "$STATUS" in
        healthy)
            log_info "Mastercontainer is healthy."
            break
            ;;
        unhealthy)
            log_error "Mastercontainer entered an unhealthy state."
            docker logs nextcloud-aio-mastercontainer --tail 50 || true
            exit 1
            ;;
        not_found)
            log_warn "Container not found yet (${ELAPSED}s / ${HEALTH_TIMEOUT}s)..."
            ;;
        *)
            log_info "Container status: ${STATUS} (${ELAPSED}s / ${HEALTH_TIMEOUT}s)..."
            ;;
    esac

    sleep $HEALTH_INTERVAL
    ELAPSED=$((ELAPSED + HEALTH_INTERVAL))
done

if [[ $ELAPSED -ge $HEALTH_TIMEOUT ]]; then
    log_error "Mastercontainer did not become healthy within ${HEALTH_TIMEOUT}s."
    docker inspect nextcloud-aio-mastercontainer || true
    exit 1
fi

# ── Print admin URL ───────────────────────────────────────────────────────────
ADMIN_HOSTNAME=""
if [[ -f "$ENV_FILE" ]]; then
    ADMIN_HOSTNAME="$(grep "^ADMIN_HOSTNAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)" || true
fi

echo ""
echo "════════════════════════════════════════════════════"
echo "  Nextcloud AIO is running!"
echo ""
if [[ -n "$ADMIN_HOSTNAME" ]]; then
    echo "  Admin panel:  https://${ADMIN_HOSTNAME}"
else
    echo "  Admin panel:  https://<ADMIN_HOSTNAME>:8080"
fi
echo ""
echo "  !! COMPLETE FIRST LOGIN NOW !!"
echo ""
echo "  The initial passphrase is displayed on the admin"
echo "  panel's first page. Until you log in and dismiss"
echo "  it, Cloudflare Access is the only barrier — anyone"
echo "  who clears it can read the passphrase off the screen."
echo ""
echo "  Open the URL above in your browser immediately."
echo "  Do not leave this session unattended until first"
echo "  login is complete and Nextcloud setup has started."
echo "════════════════════════════════════════════════════"
echo ""

log_info "Nextcloud AIO started successfully."
