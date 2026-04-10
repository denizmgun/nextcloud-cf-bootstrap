#!/usr/bin/env bash
# 07_configure_nextcloud.sh — Collect Nextcloud AIO settings and render docker-compose.yml.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"
NC_DIR="${HOME}/.nextcloud"
COMPOSE_OUT="${NC_DIR}/docker-compose.yml"

log_info "Step 07: Configure Nextcloud AIO"

# ── Pre-fill from existing .env ───────────────────────────────────────────────
_existing_nc_hostname=""
_existing_rclone_mount=""
if [[ -f "$ENV_FILE" ]]; then
    _existing_nc_hostname="$(grep "^NC_HOSTNAME=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)" || true
    _existing_rclone_mount="$(grep "^RCLONE_MOUNT_POINT=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)" || true
fi

# ── Detect system timezone ────────────────────────────────────────────────────
_sys_tz="UTC"
if [[ -f /etc/timezone ]]; then
    _sys_tz="$(cat /etc/timezone)"
elif command_exists timedatectl; then
    _sys_tz="$(timedatectl show -p Timezone --value 2>/dev/null)" || _sys_tz="UTC"
fi

# ── Prompts ───────────────────────────────────────────────────────────────────
NC_DATADIR=""
NC_TIMEZONE=""
NC_DOMAIN=""
BACKUP_LOCATION=""

prompt_optional NC_DATADIR \
    "Absolute path for Nextcloud data directory" "/var/lib/nextcloud/data"

prompt_optional NC_TIMEZONE \
    "Server timezone (IANA format, e.g. Europe/Berlin)" "$_sys_tz"

if [[ -n "$_existing_nc_hostname" ]]; then
    prompt_optional NC_DOMAIN \
        "Main domain for Nextcloud" "$_existing_nc_hostname"
else
    prompt_required NC_DOMAIN \
        "Main domain for Nextcloud (e.g. nextcloud.example.com)"
fi

_backup_default="${_existing_rclone_mount:-/var/lib/nextcloud/backup}"
prompt_optional BACKUP_LOCATION \
    "Absolute path for AIO backups" "$_backup_default"

# ── Create directories ────────────────────────────────────────────────────────
log_info "Creating Nextcloud data directory: ${NC_DATADIR}"
mkdir -p "$NC_DATADIR"

# Only create BACKUP_LOCATION if it is not an rclone mount point — the rclone
# systemd unit (script 06) owns that directory; creating it here before the
# mount is active would leave an empty directory that hides mount failures.
if [[ "$BACKUP_LOCATION" != "$_existing_rclone_mount" || -z "$_existing_rclone_mount" ]]; then
    log_info "Creating backup directory: ${BACKUP_LOCATION}"
    mkdir -p "$BACKUP_LOCATION"
else
    log_info "Backup location is the rclone mount point — skipping mkdir (mount unit owns it)."
fi

# ── Persist to .env ───────────────────────────────────────────────────────────
env_set "NC_DATADIR"        "$NC_DATADIR"        "$ENV_FILE"
env_set "NC_TIMEZONE"       "$NC_TIMEZONE"       "$ENV_FILE"
env_set "NC_DOMAIN"         "$NC_DOMAIN"         "$ENV_FILE"
env_set "BACKUP_LOCATION"   "$BACKUP_LOCATION"   "$ENV_FILE"

# ── Idempotency ───────────────────────────────────────────────────────────────
if [[ -f "$COMPOSE_OUT" ]]; then
    OVERWRITE=""
    prompt_yes_no OVERWRITE \
        "docker-compose.yml already exists at ${COMPOSE_OUT}. Overwrite?"
    if [[ "$OVERWRITE" != "yes" ]]; then
        log_info "Keeping existing compose file."
        exit 0
    fi
fi

# ── Render template ───────────────────────────────────────────────────────────
TEMPLATE="${SCRIPT_DIR}/templates/docker-compose.yml.tpl"
if [[ ! -f "$TEMPLATE" ]]; then
    log_error "Template not found: ${TEMPLATE}"
    exit 1
fi

mkdir -p "$NC_DIR"

sed \
    -e "s|{{NC_DOMAIN}}|${NC_DOMAIN}|g" \
    -e "s|{{NC_DATADIR}}|${NC_DATADIR}|g" \
    -e "s|{{NC_TIMEZONE}}|${NC_TIMEZONE}|g" \
    -e "s|{{BACKUP_LOCATION}}|${BACKUP_LOCATION}|g" \
    "$TEMPLATE" > "$COMPOSE_OUT"
chmod 600 "$COMPOSE_OUT"

log_info "Rendered docker-compose.yml to ${COMPOSE_OUT}"
log_info "Nextcloud configuration complete."
