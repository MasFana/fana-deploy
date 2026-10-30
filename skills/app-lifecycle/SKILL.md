---
name: app-lifecycle
category: devops
description: Manage application lifecycle operations including status checks, log inspection, service restarts, atomic release rollbacks, manual backups, database restoration, and safe app deletion. Use whenever an agent or user needs to inspect app health, read runtime logs, rollback a failed deployment, backup/restore data, or uninstall an app.
version: 1.1.0
tools:
  - fana-deploy
  - bash
  - curl
---

# Application Lifecycle Skill

## Scope & Trigger Context
Invoke this skill when performing day-to-day operations and maintenance on deployed applications:
- Checking application status, active releases, and HTTP response codes (`status`).
- Inspecting web server logs or Laravel application logs (`logs`).
- Restarting FrankenPHP web server worker threads and clearing opcode cache (`restart`).
- Reverting to the previous working release after a bad deployment (`rollback`).
- Creating on-demand SQLite database backups (`backup`).
- Restoring a specific historical SQLite backup (`restore`).
- Safely decommissioning an application and archiving its database (`remove`).
- Listing all active applications and domains (`list`).

## Operational Commands Reference

### 1. View App Status or System Overview
```bash
# Check detailed status of a specific app (current release, commit, DB size, HTTP origin code, public code, recent logs)
/home/fana-deploy/fana-deploy status <app_name>

# Check overall host health audit and summarize all active apps
/home/fana-deploy/fana-deploy status
```

### 2. Tail Application Logs
```bash
# Read the last 50 lines of Caddy access logs or storage/logs/laravel.log
/home/fana-deploy/fana-deploy logs <app_name>
```

### 3. Restart Web Server
```bash
# Gracefully restarts FrankenPHP under user fana with bounded GOMEMLIMIT=350MiB and clears opcode cache
/home/fana-deploy/fana-deploy restart <app_name>
```

### 4. Atomic Release Rollback
```bash
# Reverts the current symlink to the previous release in releases/, resets opcache, and reloads FrankenPHP
/home/fana-deploy/fana-deploy rollback <app_name>
```
*Note*: Also automatically runs `update_registry.py` to refresh telemetry.

### 5. Manual Database Backup
```bash
# Creates a snapshot of database.sqlite in /home/fana-deploy/deployment/backups/<app>/manual_<timestamp>.sqlite
/home/fana-deploy/fana-deploy backup <app_name>
```
Automatically prunes backups older than the 5 most recent snapshots.

### 6. Database Restore
```bash
# Overwrites shared/database/database.sqlite with the specified backup file, fixing ownership to fana:fana (664)
/home/fana-deploy/fana-deploy restore <app_name> /path/to/backup.sqlite
```

### 7. Decommission & Remove Application
```bash
# Safely decommissions an application with zero residual routing or cron jobs
/home/fana-deploy/fana-deploy remove <app_name>
```
**Decommission Pipeline Order**:
1. Creates final database snapshot in `/home/fana-deploy/deployment/backups/<app_name>/final_archive.sqlite`.
2. Deletes ingress entry from `/etc/cloudflared/config.yml` via `ingress_tool.py remove <domain>`.
3. Removes Caddy vhost `/home/fana-deploy/deployment/caddy/sites/<app_name>.caddy` and restarts FrankenPHP.
4. Purges app-specific cron schedules from crontab.
5. Deletes `/home/fana-deploy/deployment/apps/<app_name>`.
6. Updates `/home/fana-deploy/deployment/registry.json`.

### 8. List All Applications
```bash
/home/fana-deploy/fana-deploy list
```

## Capacity Guardrail
- Maximum capacity: **8 active applications**.
- If capacity is reached, new deployments are rejected by preflight until an existing app is removed.
- Memory budget per application: **10MB–30MB idle RAM**.
