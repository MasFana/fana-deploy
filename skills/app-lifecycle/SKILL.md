---
name: app-lifecycle
category: devops
description: Manage application lifecycle including status, update, rollback, and cleanup.
version: 1.0.0
---

# Application Lifecycle Skill

## Scope
Handle operational commands for deployed applications: status, logs, restart, rollback, backup, restore, and safe deletion.

## Capacity Rule
Max 8 active apps. Reject deployment if active count >= 8. Each SQLite app budget: 10-30MB RAM.

## Operations
- `status`: Check symlink target, Caddy config presence, HTTP response via origin 8088, and last log entries.
- `logs`: Tail `/home/fana-deploy/deployment/logs/<app>.log` or Laravel storage logs.
- `rollback`: Swap symlink to previous release in `releases/`, reload Caddy.
- `remove`: Disable Caddy site, remove ingress from `/etc/cloudflared/config.yml`, validate tunnel, reload Caddy, archive database, and remove app files.
