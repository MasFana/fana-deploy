#!/bin/bash
# Health monitor & audit script for fana-deploy
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logging.sh"

MEM_AVAIL=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo)
SWAP_TOTAL=$(awk '/SwapTotal/ {print int($2/1024)}' /proc/meminfo)
SWAP_FREE=$(awk '/SwapFree/ {print int($2/1024)}' /proc/meminfo)

SWAP_USED=0
SWAP_USED_PCT=0
if [ "${SWAP_TOTAL}" -gt 0 ]; then
    SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
    SWAP_USED_PCT=$(( (SWAP_USED * 100) / SWAP_TOTAL ))
fi

DISK_USED_PCT=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')

ALERT=0
ALERT_MSG=()

if [ "${MEM_AVAIL}" -lt 150 ]; then
    ALERT=1
    ALERT_MSG+=("CRITICAL: MemAvailable is ${MEM_AVAIL}MB (< 150MB threshold)!")
fi

if [ "${SWAP_USED_PCT}" -gt 70 ]; then
    ALERT=1
    ALERT_MSG+=("WARNING: Swap usage is ${SWAP_USED_PCT}% (> 70% threshold)!")
fi

if [ "${DISK_USED_PCT}" -gt 85 ]; then
    ALERT=1
    ALERT_MSG+=("WARNING: Root disk usage is ${DISK_USED_PCT}% (> 85% threshold)!")
fi

# Check for recent OOM killer events (within last 30 minutes)
UPTIME_SEC=$(cut -d. -f1 /proc/uptime)
RECENT_OOM=$(awk -v up="${UPTIME_SEC}" '
  match($0, /^\[ *([0-9]+)\./, arr) {
    if ((up - arr[1]) < 1800 && ($0 ~ /oom[-_]killer|Out of memory/)) {
      print $0
    }
  }' <(dmesg) || true)

if [ -n "${RECENT_OOM}" ]; then
    ALERT=1
    ALERT_MSG+=("CRITICAL: Recent OOM killer activity detected in dmesg!")
fi

# Core services check
SKRIPSI_STATUS="DOWN"
if curl -s -f -u fana:fana -o /dev/null --connect-timeout 2 http://127.0.0.1:8080/; then
    SKRIPSI_STATUS="UP (200 OK)"
else
    ALERT=1
    ALERT_MSG+=("CRITICAL: Skripsi viewer (port 8080) is DOWN!")
fi

FRANKEN_STATUS="DOWN"
if curl -s -f -o /dev/null --connect-timeout 2 http://127.0.0.1:8088/; then
    FRANKEN_STATUS="UP (200 OK)"
else
    ALERT=1
    ALERT_MSG+=("WARNING: FrankenPHP (port 8088) is DOWN!")
fi

TUNNEL_STATUS="DOWN"
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    TUNNEL_STATUS="UP"
else
    ALERT=1
    ALERT_MSG+=("CRITICAL: Cloudflared tunnel is DOWN!")
fi

echo "=== System Health Audit ==="
echo "MemAvailable:  ${MEM_AVAIL} MB"
echo "Swap Usage:    ${SWAP_USED} MB / ${SWAP_TOTAL} MB (${SWAP_USED_PCT}%)"
echo "Disk Usage:    ${DISK_USED_PCT}% on /"
echo "Skripsi :8080: ${SKRIPSI_STATUS}"
echo "Franken :8088: ${FRANKEN_STATUS}"
echo "Cloudflared:   ${TUNNEL_STATUS}"
echo ""
echo "=== Top 3 RAM-Consuming Processes ==="
ps -o pid,user,comm,vsz,rss 2>/dev/null | sort -k5 -rn | sed -n '1,4p' || true

if [ "${ALERT}" -eq 1 ]; then
    echo ""
    log_error "Health Alert Triggered:"
    for msg in "${ALERT_MSG[@]}"; do
        echo "  - ${msg}"
    done
    if [ -n "${RECENT_OOM}" ]; then
        echo "Recent OOM events:"
        echo "${RECENT_OOM}"
    fi
    exit 1
else
    echo ""
    log_success "All health checks normal."
    exit 0
fi
