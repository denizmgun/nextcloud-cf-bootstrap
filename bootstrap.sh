#!/usr/bin/env bash
# bootstrap.sh — Master script: calls all module scripts in sequence.
# Usage: sudo bash bootstrap.sh [--dry-run]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

ENV_FILE="${HOME}/.nextcloud/.env"
DRY_RUN=false

for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && DRY_RUN=true
done

check_root

# Each entry: "NUM:Human Name:relative/path/to/script.sh"
STEPS=(
    "01:Install Docker:scripts/01_install_docker.sh"
    "02:Install cloudflared:scripts/02_install_cloudflared.sh"
    "03:Prompt rclone:scripts/03_prompt_rclone.sh"
    "04:Install rclone:scripts/04_install_rclone.sh"
    "05:Configure tunnel:scripts/05_configure_tunnel.sh"
    "06:Configure rclone:scripts/06_configure_rclone.sh"
    "07:Configure Nextcloud:scripts/07_configure_nextcloud.sh"
    "08:Connect tunnel:scripts/08_connect_tunnel.sh"
    "09:Protect admin panel:scripts/09_protect_adminpanel.sh"
    "10:Run Nextcloud:scripts/10_run_nextcloud.sh"
)

declare -A STEP_STATUS

# ── Helpers ───────────────────────────────────────────────────────────────────

print_summary() {
    echo ""
    echo "══════════════════════════════════════════════════"
    printf "  %-6s %-30s %s\n" "Step" "Name" "Status"
    echo "──────────────────────────────────────────────────"
    for entry in "${STEPS[@]}"; do
        IFS=: read -r num name _ <<< "$entry"
        local status="${STEP_STATUS[$num]:-not run}"
        printf "  %-6s %-30s %s\n" "$num" "$name" "$status"
    done
    echo "══════════════════════════════════════════════════"
}

run_step() {
    local num="$1"
    local name="$2"
    local script="${SCRIPT_DIR}/$3"

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would run: ${script}"
        STEP_STATUS["$num"]="dry-run"
        return 0
    fi

    echo ""
    log_info "━━━ Step ${num}: ${name} ━━━"
    if bash "$script"; then
        STEP_STATUS["$num"]="✓"
        log_info "Step ${num} completed successfully."
    else
        STEP_STATUS["$num"]="✗"
        log_error "Step ${num} (${name}) failed. Aborting bootstrap."
        print_summary
        exit 1
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────

mkdir -p "${HOME}/.nextcloud"
chmod 700 "${HOME}/.nextcloud"

if $DRY_RUN; then
    log_warn "Running in DRY-RUN mode — no changes will be made."
fi

for entry in "${STEPS[@]}"; do
    IFS=: read -r num name script_rel <<< "$entry"

    # After step 03, skip rclone-dependent steps if RCLONE_ENABLED != yes
    if [[ "$num" == "04" || "$num" == "06" ]]; then
        rclone_enabled=""
        if [[ -f "$ENV_FILE" ]]; then
            rclone_enabled="$(grep "^RCLONE_ENABLED=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-)" || true
        fi
        if [[ "$rclone_enabled" != "yes" ]]; then
            log_info "Step ${num}: Skipping (RCLONE_ENABLED != yes)"
            STEP_STATUS["$num"]="skipped"
            continue
        fi
    fi

    run_step "$num" "$name" "$script_rel"
done

print_summary

echo ""
log_info "Bootstrap complete."
