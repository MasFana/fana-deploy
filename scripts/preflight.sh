#!/bin/bash
# Preflight resource and capacity check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

APP_NAME="${1:-}"
CHECK_DIR="${2:-}"

# 1. Capacity check
CONFIG_FILE="/home/fana-deploy/deployment/config.yml"
MAX_APPS=8
if [ -f "${CONFIG_FILE}" ]; then
    CFG_MAX=$(awk -F': ' '$1 == "max_apps" {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' "${CONFIG_FILE}" | head -n1)
    if [ -n "${CFG_MAX}" ]; then
        MAX_APPS="${CFG_MAX}"
    fi
fi

APPS_DIR="/home/fana-deploy/deployment/apps"
mkdir -p "${APPS_DIR}"
ACTIVE_COUNT=0
if [ -d "${APPS_DIR}" ]; then
    ACTIVE_COUNT=$(find "${APPS_DIR}" -mindepth 1 -maxdepth 1 -type d | wc -l)
fi

if [ "${ACTIVE_COUNT}" -ge "${MAX_APPS}" ] && [ -n "${APP_NAME}" ] && [ ! -d "${APPS_DIR}/${APP_NAME}" ]; then
    log_error "Capacity exceeded: ${ACTIVE_COUNT}/${MAX_APPS} active apps. Rejecting new app deploy."
    exit 1
fi

# 2. Memory & Swap check
MEM_AVAIL=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
SWAP_FREE=$(awk '/SwapFree/ {print int($2/1024)}' /proc/meminfo)
TOTAL_AVAIL=$(( MEM_AVAIL + SWAP_FREE ))

log_info "Preflight Memory: MemAvailable=${MEM_AVAIL}MB, SwapFree=${SWAP_FREE}MB, Total=${TOTAL_AVAIL}MB"

if [ "${TOTAL_AVAIL}" -lt 600 ]; then
    log_error "Aborting deploy: MemAvailable + SwapFree is ${TOTAL_AVAIL}MB (< 600MB minimum required)."
    exit 1
fi

if [ "${ACTIVE_COUNT}" -eq 0 ] && [ "${MEM_AVAIL}" -lt 400 ]; then
    log_warn "MemAvailable is ${MEM_AVAIL}MB (< 400MB at idle). Consider freeing memory before deploying."
fi

# 3. Disk space check
# Require min 1.5GB free on /
DISK_AVAIL_KB=$(df -k / | awk 'NR==2 {print $4}')
DISK_AVAIL_MB=$(( DISK_AVAIL_KB / 1024 ))
log_info "Preflight Disk: Available=${DISK_AVAIL_MB}MB"

if [ "${DISK_AVAIL_MB}" -lt 1500 ]; then
    log_error "Aborting deploy: Free disk space is ${DISK_AVAIL_MB}MB (< 1500MB minimum required)."
    exit 1
fi

# 4. Dependency / Stack check if directory given
if [ -n "${CHECK_DIR}" ] && [ -d "${CHECK_DIR}" ]; then
    log_info "Checking forbidden dependencies in ${CHECK_DIR}..."
    if [ -f "${CHECK_DIR}/composer.json" ]; then
        if grep -Ei '"(predis/predis|laravel/horizon|laravel/octane)"' "${CHECK_DIR}/composer.json" >/dev/null 2>&1; then
            if [ "${ALLOW_HEAVY_STACK:-0}" != "1" ]; then
                log_error "Forbidden dependency found (Horizon/Octane/Redis) in composer.json without explicit approval (ALLOW_HEAVY_STACK=1)."
                exit 1
            fi
        fi
    fi
fi

log_success "Preflight checks passed (Capacity: ${ACTIVE_COUNT}/${MAX_APPS} apps, RAM+Swap: ${TOTAL_AVAIL}MB, Disk: ${DISK_AVAIL_MB}MB)"
exit 0
