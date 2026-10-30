#!/bin/bash
# Rollback application to previous release
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

APP_NAME="${1:-}"
if [ -z "${APP_NAME}" ]; then
    log_error "Usage: $0 <app_name>"
    exit 1
fi

APP_DIR="/home/fana-deploy/deployment/apps/${APP_NAME}"
RELEASES_DIR="${APP_DIR}/releases"
CURRENT_LINK="${APP_DIR}/current"

if [ ! -d "${RELEASES_DIR}" ] || [ ! -L "${CURRENT_LINK}" ]; then
    log_error "No active release found for ${APP_NAME}."
    exit 1
fi

CURRENT_TARGET=$(readlink -f "${CURRENT_LINK}")
CURRENT_NAME=$(basename "${CURRENT_TARGET}")

# List all releases sorted descending
RELEASES=($(ls -1d "${RELEASES_DIR}"/* 2>/dev/null | sort -r))
PREV_RELEASE=""

for rel in "${RELEASES[@]}"; do
    if [ "$(basename "${rel}")" != "${CURRENT_NAME}" ]; then
        PREV_RELEASE="${rel}"
        break
    fi
done

if [ -z "${PREV_RELEASE}" ] || [ ! -d "${PREV_RELEASE}" ]; then
    log_error "No previous release found to roll back to for ${APP_NAME}."
    exit 1
fi

log_info "Rolling back ${APP_NAME} from ${CURRENT_NAME} to $(basename "${PREV_RELEASE}")..."

# Atomically update symlink
ln -sfn "${PREV_RELEASE}" "${CURRENT_LINK}"

# Clear opcache if php cli opcache reset tool available
if command -v php >/dev/null 2>&1; then
    php -r "if (function_exists('opcache_reset')) opcache_reset();" 2>/dev/null || true
fi

# Reload FrankenPHP / Caddy if running
if pgrep -f "frankenphp run" >/dev/null 2>&1; then
    log_info "Reloading FrankenPHP configuration..."
    /usr/local/bin/frankenphp reload --config /home/fana-deploy/deployment/caddy/Caddyfile 2>/dev/null || {
        pkill -HUP -f "frankenphp run" 2>/dev/null || true
    }
fi

log_success "Successfully rolled back ${APP_NAME} to $(basename "${PREV_RELEASE}")."
