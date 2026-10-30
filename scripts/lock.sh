#!/bin/bash
# Lock manager for fana-deploy
# App lock & Global heavy lock (nice -n 10, ionice -c3)
set -euo pipefail

RUN_DIR="/home/fana-deploy/deployment/run"
mkdir -p "${RUN_DIR}"

HEAVY_LOCK="${RUN_DIR}/heavy.lock"

run_nicely() {
    if command -v ionice >/dev/null 2>&1; then
        nice -n 10 ionice -c3 "$@"
    else
        nice -n 10 "$@"
    fi
}

with_app_lock() {
    local app="$1"
    shift
    local lock_file="${RUN_DIR}/${app}.lock"
    flock -x -w 300 "${lock_file}" "$@"
}

with_heavy_lock() {
    flock -x -w 600 "${HEAVY_LOCK}" bash -c '
        if command -v ionice >/dev/null 2>&1; then
            exec nice -n 10 ionice -c3 "$@"
        else
            exec nice -n 10 "$@"
        fi
    ' -- "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        app)
            shift
            app_name="$1"
            shift
            with_app_lock "${app_name}" "$@"
            ;;
        heavy)
            shift
            with_heavy_lock "$@"
            ;;
        *)
            echo "Usage: $0 {app <app_name>|heavy} <command...>"
            exit 1
            ;;
    esac
fi
