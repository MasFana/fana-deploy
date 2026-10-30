---
name: health-monitor
category: devops
description: Monitor system RAM, swap, disk space, OOM killer invocations, and core service health without disturbing background processes. Use when diagnosing high load, checking resource availability before a deployment, auditing system health, or inspecting top memory-consuming processes on Alpine Linux aarch64.
version: 1.1.0
tools:
  - bash
  - curl
  - dmesg
  - top
  - ps
---

# Health Monitor Skill

## Scope & Trigger Context
Use this skill whenever:
- Performing pre-deployment checks or verifying host readiness.
- Investigating system slowness, out-of-memory errors (OOM exit code 137), or swap pressure.
- Auditing active services (FrankenPHP, Skripsi viewer, Cloudflare tunnel).
- Responding to telemetry alerts or checking system telemetry logs.

## Non-Disruption Guarantee
Under **NO circumstances** kill, signal, or disrupt:
1. `skripsi.fmo.qzz.io` viewer on port 8080 (`python3` process).
2. `cloudflared tunnel` daemon process.
3. System watchdogs (`/opt/skripsi_watchdog.sh` or `templates/watchdog.sh`).

## Health Thresholds & Alert Matrix

| Metric | Warning Threshold | Critical Threshold | Agent Action |
| :--- | :--- | :--- | :--- |
| **MemAvailable** | < 250 MB | < 150 MB | Reject new deploys. Check top 3 RSS processes. Run memory cleanup if safe. |
| **Swap Usage** | > 50% | > 70% | Avoid concurrent builds (npm/composer). Ensure heavy lock is held. |
| **Root Disk (/)**| > 75% | > 85% | Prune old releases and backups via `fana-deploy status`. Delete temporary files. |
| **dmesg OOM** | - | Any event < 30m | Inspect offending PID. Report to operator before running heavy tasks. |
| **Port 8080** | - | HTTP non-200 | Critical service failure. Check python3 process. |
| **Port 8088** | - | HTTP non-200 | Web server down. Inspect `deployment/logs/frankenphp.stdout.log`. Restart web server. |
| **Tunnel** | - | Process dead | Cloudflare tunnel down. Check `pgrep -f "cloudflared tunnel"`. Restart tunnel. |

## Audit Execution Commands

### 1. Comprehensive System Audit
Run the built-in system health audit:
```bash
/home/fana-deploy/fana-deploy audit
# Or execute the audit script directly:
/home/fana-deploy/scripts/health_check.sh
```
Exit code `0` indicates all health parameters are normal. Exit code `1` triggers an alert with diagnostic reasons.

### 2. Alpine / BusyBox RAM Diagnostics
```bash
# Display top processes sorted by Resident Set Size (RSS physical RAM)
top -b -n1 -m | head -n 20

# Standard memory statistics
free -h

# Kernel memory breakdown
head -n 15 /proc/meminfo
```

### 3. Check for Recent Kernel OOM Events
```bash
# Check dmesg for OOM killer invocations
dmesg | grep -Ei "oom[-_]killer|out of memory|killed process" | tail -n 10
```

### 4. Telemetry Registry Inspection
Read the live application telemetry cache updated by the monitoring pipeline:
```bash
cat /home/fana-deploy/deployment/registry.json
```
To force a telemetry update across all apps:
```bash
/usr/bin/python3 /home/fana-deploy/scripts/update_registry.py
```
