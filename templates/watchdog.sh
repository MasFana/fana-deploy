#!/bin/bash
# FrankenPHP Service Watchdog
set -euo pipefail

ORIGIN_PORT="8088"
CADDYFILE="/home/fana-deploy/deployment/caddy/Caddyfile"
LOG_FILE="/home/fana-deploy/deployment/logs/watchdog.log"
RUN_USER="fana"

mkdir -p /home/fana-deploy/deployment/logs

if ! curl -s -f -o /dev/null --connect-timeout 2 "http://127.0.0.1:${ORIGIN_PORT}/"; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] FrankenPHP down on port ${ORIGIN_PORT}. Restarting..." >> "${LOG_FILE}"
    pkill -9 -f "frankenphp run" 2>/dev/null || true
    sleep 1
    export GOMEMLIMIT=350MiB
    export GOGC=75
    su -s /bin/bash "${RUN_USER}" -c "GOMEMLIMIT=350MiB GOGC=75 nohup /usr/local/bin/frankenphp run --config ${CADDYFILE} --adapter caddyfile >> /home/fana-deploy/deployment/logs/frankenphp.stdout.log 2>&1 &"
fi
