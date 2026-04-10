#!/usr/bin/env bash
# lib/common.sh — Shared helpers, sourced by all scripts.
# Do NOT set -e here; callers own their own error handling.

# ── Colors ────────────────────────────────────────────────────────────────────
_RED='\033[0;31m'
_YELLOW='\033[1;33m'
_GREEN='\033[0;32m'
_CYAN='\033[0;36m'
_RESET='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
log_info()  { echo -e "${_GREEN}[$(date '+%H:%M:%S')] INFO${_RESET}  $*"; }
log_warn()  { echo -e "${_YELLOW}[$(date '+%H:%M:%S')] WARN${_RESET}  $*" >&2; }
log_error() { echo -e "${_RED}[$(date '+%H:%M:%S')] ERROR${_RESET} $*" >&2; }

# ── Root check ────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root or with sudo."
        exit 1
    fi
}

# ── Prompts ───────────────────────────────────────────────────────────────────

# prompt_required <varname> <prompt text>
# Loops until the user provides a non-empty value.
prompt_required() {
    local var="$1"
    local msg="$2"
    local value=""
    while [[ -z "$value" ]]; do
        read -rp "$(echo -e "${_CYAN}${msg}${_RESET}: ")" value
    done
    printf -v "$var" '%s' "$value"
}

# prompt_optional <varname> <prompt text> <default>
# Accepts empty input and falls back to the supplied default.
prompt_optional() {
    local var="$1"
    local msg="$2"
    local default="$3"
    local value=""
    read -rp "$(echo -e "${_CYAN}${msg} [${default}]${_RESET}: ")" value
    printf -v "$var" '%s' "${value:-$default}"
}

# prompt_yes_no <varname> <question>
# Stores "yes" or "no" in varname.
prompt_yes_no() {
    local var="$1"
    local msg="$2"
    local answer=""
    while true; do
        read -rp "$(echo -e "${_CYAN}${msg} [y/N]${_RESET}: ")" answer
        case "${answer,,}" in
            y|yes) printf -v "$var" '%s' "yes"; return 0 ;;
            n|no|"") printf -v "$var" '%s' "no";  return 0 ;;
            *) log_warn "Please answer y or n." ;;
        esac
    done
}

# ── Utility ───────────────────────────────────────────────────────────────────

command_exists() { command -v "$1" &>/dev/null; }

# env_set <KEY> <VALUE> <FILE>
# Idempotently writes or updates KEY=VALUE in FILE.
# Creates the file (and parent directories) if necessary, mode 600.
env_set() {
    local key="$1"
    local value="$2"
    local file="$3"
    mkdir -p "$(dirname "$file")"
    touch "$file"
    chmod 600 "$file"
    if grep -q "^${key}=" "$file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    else
        echo "${key}=${value}" >> "$file"
    fi
}

# require_env <FILE> <KEY>
# Exits with an error if KEY is missing or empty in FILE.
require_env() {
    local file="$1"
    local key="$2"
    if [[ ! -f "$file" ]] || ! grep -q "^${key}=" "$file"; then
        log_error "Required config key '${key}' not found in ${file}"
        exit 1
    fi
    local value
    value="$(grep "^${key}=" "$file" | cut -d= -f2-)"
    if [[ -z "$value" ]]; then
        log_error "Required config key '${key}' is empty in ${file}"
        exit 1
    fi
}
