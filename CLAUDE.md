# CLAUDE.md — Operating Instructions for Claude Code

> Instructions and constraints for Claude Code operating on `fana-deploy`.

## Project Overview
`fana-deploy` is an autonomous deployment orchestrator for Laravel applications on resource-constrained **Alpine Linux aarch64** (1GB–2GB RAM). It enforces zero-downtime atomic symlink deployments, SQLite WAL storage, and strict memory limits ($\le 250\text{MB}$ idle, $\le 350\text{MB}$ peak) via FrankenPHP.

---

## The Non-Negotiable Invariants

1. **Port 8080 is Untouchable**: `skripsi.fmo.qzz.io` on `127.0.0.1:8080` (Python viewer) must NEVER be killed, stopped, or removed from `/etc/cloudflared/config.yml`.
2. **Classic PHP Mode Only**: Web apps run via FrankenPHP's `php_server` directive. Never introduce Octane or FrankenPHP worker mode without documented operator consent.
3. **Strict SQLite Storage**: All apps must store state in `/home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite` using `PRAGMA journal_mode=WAL;` and `PRAGMA synchronous=NORMAL;`. Reject MySQL, Postgres, Redis, and Horizon.
4. **Heavy Lock Serialization**: Memory-intensive tasks (Composer, npm build, artisan migrate) must run under `/home/fana-deploy/deployment/run/heavy.lock` using `nice -n 10` and `ionice -c3`. Never run concurrent builds.
5. **Atomic Release Switching**: Code lives in `releases/<timestamp>` and is activated via the `current` symlink. Never clone or build directly in `current`.
6. **Post-Deploy Cache Build**: Run `php artisan optimize` once after the symlink swap, then leave the caches alone. Never `optimize:clear` while a worker is live and cache/session live in the database.
7. **Capacity Ceiling**: Max 8 active applications. Reject new deploys if active count $\ge 8$.

---

## Core CLI Cheat Sheet

Autonomous tasks should use `/home/fana-deploy/fana-deploy` directly:

```bash
# Deploy a new application
/home/fana-deploy/fana-deploy deploy <git_url> [as <app_name>] [domain <hostname>]

# Update an existing application to latest git commit
/home/fana-deploy/fana-deploy update <app_name>

# Rollback to the previous release
/home/fana-deploy/fana-deploy rollback <app_name>

# Check system health & all apps
/home/fana-deploy/fana-deploy status

# Detailed status of a single app
/home/fana-deploy/fana-deploy status <app_name>

# Tail logs (Caddy access log or Laravel application log)
/home/fana-deploy/fana-deploy logs <app_name>

# Restart FrankenPHP web server & reset opcache
/home/fana-deploy/fana-deploy restart <app_name>

# Snapshot database (retains newest 5)
/home/fana-deploy/fana-deploy backup <app_name>

# Restore database from snapshot
/home/fana-deploy/fana-deploy restore <app_name> <path_to_backup.sqlite>

# Safely remove application (archives DB, removes ingress & Caddy vhost)
/home/fana-deploy/fana-deploy remove <app_name>

# List active apps
/home/fana-deploy/fana-deploy list

# Run full health audit script
/home/fana-deploy/fana-deploy audit
```

---

## Quick Diagnostics & Fixes

### 1. Exit Code 137 (OOM)
- Check dmesg: `dmesg | tail -n 25`
- Check memory: `free -h` and `top -b -n1 -m | head -n 15`
- Ensure heavy lock is used: `/home/fana-deploy/scripts/lock.sh heavy env COMPOSER_MEMORY_LIMIT=1G composer install ...`

### 2. HTTP 500 View / Route Error
- Clear Laravel framework caches:
  ```bash
  cd /home/fana-deploy/deployment/apps/<app>/current
  php artisan route:clear && php artisan optimize
  ```
- Restart FrankenPHP: `/home/fana-deploy/fana-deploy restart <app>`

### 3. SQLite "database is locked"
- Set WAL mode & permissions:
  ```bash
  DB="/home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite"
  sqlite3 "${DB}" 'PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;'
  chown -R fana:fana "$(dirname "${DB}")"
  chmod 775 "$(dirname "${DB}")" && chmod 664 "${DB}"*
  ```

### 4. Cloudflare Ingress Failure
- Check diff with backup: `diff -u /etc/cloudflared/config.yml.bak /etc/cloudflared/config.yml`
- Revert: `cp /etc/cloudflared/config.yml.bak /etc/cloudflared/config.yml && cloudflared tunnel ingress validate`

---

## Code & Scripting Conventions

- **Shell**: Use POSIX/BusyBox-compatible bash syntax on Alpine Linux (`set -euo pipefail`).
- **Permissions**: Application code and runtime files are owned by `fana:fana`.
- **Skills Directory**: See `skills/*/SKILL.md` and machine-readable `skills/index.json` for detailed contracts.
