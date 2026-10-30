#!/bin/bash
# Logging utilities for fana-deploy

LOG_DIR="/home/fana-deploy/deployment/logs"
mkdir -p "${LOG_DIR}"

log_ts() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo -e "\033[0;34m[$(log_ts)] [INFO]\033[0m $*"
    echo "[$(log_ts)] [INFO] $*" >> "${LOG_DIR}/deploy.log"
}

log_warn() {
    echo -e "\033[0;33m[$(log_ts)] [WARN]\033[0m $*" >&2
    echo "[$(log_ts)] [WARN] $*" >> "${LOG_DIR}/deploy.log"
}

log_error() {
    echo -e "\033[0;31m[$(log_ts)] [ERROR]\033[0m $*" >&2
    echo "[$(log_ts)] [ERROR] $*" >> "${LOG_DIR}/deploy.log"
}

log_success() {
    echo -e "\033[0;32m[$(log_ts)] [OK]\033[0m $*"
    echo "[$(log_ts)] [OK] $*" >> "${LOG_DIR}/deploy.log"
}
