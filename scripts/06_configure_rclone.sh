#!/usr/bin/env bash
# 06_configure_rclone.sh — Interactive rclone remote setup and systemd mount unit.
# Only runs when RCLONE_ENABLED=yes in ~/.nextcloud/.env.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"
SYSTEMD_UNIT="/etc/systemd/system/rclone-backup-mount.service"

# ── Guard ─────────────────────────────────────────────────────────────────────
if [[ -f "$ENV_FILE" ]] && grep -q "^RCLONE_ENABLED=no$" "$ENV_FILE"; then
    log_info "RCLONE_ENABLED is 'no'. Skipping rclone configuration."
    exit 0
fi

log_info "Step 06: Configure rclone Mount"

if ! command_exists rclone; then
    log_error "rclone is not installed. Run script 04 first."
    exit 1
fi

# ── Remote type menu ──────────────────────────────────────────────────────────
echo ""
echo "Common rclone remote types:"
echo "  1) sftp      — SSH/SFTP server (also used for BorgBase)"
echo "  2) s3        — Amazon S3 or S3-compatible (Wasabi, MinIO, etc.)"
echo "  3) b2        — Backblaze B2"
echo "  4) ftp       — FTP server"
echo "  5) onedrive  — Microsoft OneDrive"
echo "  6) drive     — Google Drive"
echo "  7) other     — Enter type manually"
echo ""

REMOTE_TYPE_CHOICE=""
prompt_required REMOTE_TYPE_CHOICE "Select remote type (1-7 or enter type name directly)"

case "$REMOTE_TYPE_CHOICE" in
    1) RCLONE_REMOTE_TYPE="sftp" ;;
    2) RCLONE_REMOTE_TYPE="s3" ;;
    3) RCLONE_REMOTE_TYPE="b2" ;;
    4) RCLONE_REMOTE_TYPE="ftp" ;;
    5) RCLONE_REMOTE_TYPE="onedrive" ;;
    6) RCLONE_REMOTE_TYPE="drive" ;;
    7) prompt_required RCLONE_REMOTE_TYPE "Enter rclone remote type" ;;
    # If they typed a type name directly, use it as-is
    *) RCLONE_REMOTE_TYPE="$REMOTE_TYPE_CHOICE" ;;
esac

echo ""
log_info "Launching interactive rclone config..."
log_info "When prompted for a remote name, choose something memorable (e.g. 'nextcloud-backup')."
log_info "Select type '${RCLONE_REMOTE_TYPE}' and follow the prompts for credentials."
echo ""
rclone config

# ── Post-config prompts ───────────────────────────────────────────────────────
echo ""
RCLONE_REMOTE_NAME=""
prompt_required RCLONE_REMOTE_NAME \
    "Enter the remote name you just configured (must match exactly)"

RCLONE_REMOTE_PATH=""
prompt_required RCLONE_REMOTE_PATH \
    "Path within the remote to mount (e.g. /backups or bucket-name/path)"

RCLONE_MOUNT_POINT=""
prompt_optional RCLONE_MOUNT_POINT \
    "Local mount point" "/mnt/nextcloud-backup"

# ── Create mount point ────────────────────────────────────────────────────────
mkdir -p "$RCLONE_MOUNT_POINT"
log_info "Mount point ready: ${RCLONE_MOUNT_POINT}"

# ── Systemd unit ──────────────────────────────────────────────────────────────
log_info "Writing systemd unit to ${SYSTEMD_UNIT}..."
cat > "$SYSTEMD_UNIT" <<EOF
[Unit]
Description=rclone mount for Nextcloud backup storage
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount ${RCLONE_REMOTE_NAME}:${RCLONE_REMOTE_PATH} ${RCLONE_MOUNT_POINT} \\
  --config /root/.config/rclone/rclone.conf \\
  --vfs-cache-mode writes \\
  --allow-other
ExecStop=/bin/fusermount -u ${RCLONE_MOUNT_POINT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

log_info "Enabling and starting rclone-backup-mount service..."
systemctl daemon-reload
systemctl enable --now rclone-backup-mount

# ── Validate mount ────────────────────────────────────────────────────────────
MAX_RETRIES=5
RETRY_INTERVAL=3
log_info "Waiting for mount to become active..."
for i in $(seq 1 $MAX_RETRIES); do
    if mountpoint -q "$RCLONE_MOUNT_POINT"; then
        log_info "Mount verified at ${RCLONE_MOUNT_POINT}"
        break
    fi
    if [[ $i -eq $MAX_RETRIES ]]; then
        log_error "Mount point ${RCLONE_MOUNT_POINT} is not active after ${MAX_RETRIES} attempts."
        systemctl status rclone-backup-mount --no-pager || true
        exit 1
    fi
    log_warn "Mount not ready yet (${i}/${MAX_RETRIES}). Retrying in ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

# ── Persist config ────────────────────────────────────────────────────────────
env_set "RCLONE_MOUNT_POINT"  "$RCLONE_MOUNT_POINT"  "$ENV_FILE"
env_set "RCLONE_REMOTE_NAME"  "$RCLONE_REMOTE_NAME"  "$ENV_FILE"
env_set "RCLONE_REMOTE_TYPE"  "$RCLONE_REMOTE_TYPE"  "$ENV_FILE"

log_info "rclone configuration complete."
