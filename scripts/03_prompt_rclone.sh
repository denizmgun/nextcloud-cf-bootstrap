#!/usr/bin/env bash
# 03_prompt_rclone.sh — Ask whether the user wants rclone remote backup storage.
# Writes RCLONE_ENABLED=yes|no to ~/.nextcloud/.env.
# Always exits 0 — the master script reads the env value to decide branching.
set -euo pipefail
trap 'log_error "Error in ${BASH_SOURCE[0]} at line ${LINENO}"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"

log_info "Step 03: Remote Backup Storage Decision"

echo ""
echo "Nextcloud AIO supports an external backup destination accessible via rclone."
echo "Compatible backends include: SFTP/BorgBase, Amazon S3, Backblaze B2, FTP, and more."
echo ""

RCLONE_ENABLED=""
prompt_yes_no RCLONE_ENABLED \
    "Do you have an external storage location (e.g. BorgBase, S3, SFTP) that you want to mount as the Nextcloud backup destination?"

env_set "RCLONE_ENABLED" "$RCLONE_ENABLED" "$ENV_FILE"

if [[ "$RCLONE_ENABLED" == "yes" ]]; then
    log_info "rclone backup enabled. Scripts 04 and 06 will run."
else
    log_info "rclone backup skipped. Scripts 04 and 06 will be skipped."
    log_info "Backups will default to a local path configured in step 07."
fi

exit 0
