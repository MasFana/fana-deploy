---
name: laravel-deploy
category: devops
description: Deploy or update Laravel applications on Alpine Linux aarch64 with atomic zero-downtime symlinks, SQLite WAL database, locked composer/npm builds, and strict memory budgeting (<=250MB FrankenPHP ceiling). Use whenever a user or agent requests deploying a new Laravel repo, upgrading a Laravel app, configuring a new Laravel project, or running Laravel migrations.
version: 1.1.0
tools:
  - fana-deploy
  - bash
  - git
  - composer
  - php
  - sqlite3
---

# Laravel Deploy Skill

## Scope & Trigger Context
Use this skill whenever:
- Deploying a new Laravel application from a Git repository.
- Upgrading or redeploying an existing Laravel application.
- Managing low-memory PHP/Laravel production stacks on Alpine aarch64.
- Setting up SQLite databases, environment configs, or build pipelines under strict resource limits.

## Core Architectural Invariants
1. **Classic PHP Mode Only**: Must run under FrankenPHP's `php_server` directive. Never use Octane or FrankenPHP worker mode unless explicitly permitted by the operator.
2. **SQLite WAL Database**: Strict SQLite usage (`shared/database/database.sqlite`). Reject MySQL, PostgreSQL, Redis, and Horizon dependencies during preflight.
3. **Heavy Process Serialization**: All memory/CPU-intensive tasks (Composer install, npm build, database migrations) must run serialized under `/home/fana-deploy/deployment/run/heavy.lock` using `nice -n 10` and `ionice -c3`.
4. **Composer Constraints**:
   - Always run: `COMPOSER_MEMORY_LIMIT=1G composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction`.
   - Never run `composer update` in production.
   - Require `composer.lock`. If missing, abort immediately.
   - Verify Alpine PHP packages match `composer.lock` requirements (e.g., Laravel 11/12+ requires PHP 8.2-8.4+).
5. **Frontend Asset Strategy**:
   - If `public/build` exists in the repository, skip npm execution entirely.
   - If `package.json` exists without prebuilt assets, run under heavy lock: `NODE_OPTIONS=--max-old-space-size=768 npm ci && npm run build` (fallback to `npm install` if no `package-lock.json`).
   - Immediately delete `node_modules/` after build to preserve disk and inode space.
6. **Queue & Cron Rules**:
   - No persistent queue daemon.
   - Laravel scheduler runs every minute via cron: `php artisan schedule:run`.
   - If database queues are used, process via cron with `--stop-when-empty --max-time=50`.
7. **Release Retention**: Retain the 3 most recent releases in `releases/` and 5 database backups in `backups/<app>/`.

## Application Directory Layout
```
/home/fana-deploy/deployment/apps/<app>/
  ├── current -> releases/<timestamp>
  ├── meta.json
  ├── releases/
  │   ├── 20261028120000/
  │   └── 20261030150000/ (current active release)
  └── shared/
      ├── .env
      ├── database/
      │   ├── database.sqlite
      │   ├── database.sqlite-wal
      │   └── database.sqlite-shm
      └── storage/
          ├── app/
          ├── framework/
          │   ├── cache/data/
          │   ├── sessions/
          │   └── views/
          └── logs/
```

## Primary Execution Workflow

### 1. Deploy New Application
```bash
/home/fana-deploy/fana-deploy deploy <git_url> [as <app_name>] [domain <domain>]
```
- `<git_url>`: Git clone URL (HTTPS or SSH).
- `as <app_name>`: (Optional) Lowercase alphanumeric app identifier. Defaults to git repo name.
- `domain <domain>`: (Optional) Target FQDN. Defaults to `<app_name>.fmo.qzz.io`.

### 2. Update Existing Application
```bash
/home/fana-deploy/fana-deploy update <app_name>
```
Extracts origin URL and domain, pulls fresh code into a new timestamped release directory, runs locked build and migrations, clears caches, and switches the symlink atomically.

### 3. Post-Deployment Verification & Cache Barrier
Immediately after code activation or symlink swap, verify:
```bash
# Clear caches to avoid stale compiled route/view artifacts
cd /home/fana-deploy/deployment/apps/<app_name>/current
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear

# Probe local FrankenPHP loopback with Host header
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: <domain>" http://127.0.0.1:8088/

# Probe public Cloudflare HTTPS endpoint
curl -s -o /dev/null -w "%{http_code}\n" --connect-timeout 5 "https://<domain>/"
```

## Diagnostic & Failure Handling
| Failure Symptom | Cause | Autonomous Recovery Procedure |
| :--- | :--- | :--- |
| **Exit code 137 during composer/npm** | Out of Memory (OOM Killer) | Check `dmesg \| tail -n 20`. Ensure no concurrent heavy lock is running. Run `fana-deploy audit` to check MemAvailable. Retry once under `lock.sh heavy`. |
| **HTTP 500: View/Route Not Found** | Stale compiled cache files across releases | Run artisan cache clear barrier (`config:clear`, `route:clear`, `view:clear`, `cache:clear`). Then restart FrankenPHP: `/home/fana-deploy/fana-deploy restart <app_name>`. |
| **Preflight Failure: RAM < 600MB** | System memory + swap insufficient | Check active memory with `free -h` and `ps -o pid,user,comm,vsz,rss \| sort -k5 -rn`. If needed, clear page cache `sync && echo 3 > /proc/sys/vm/drop_caches`. |
| **Capacity Exceeded (>= 8 apps)** | Host resource limit reached | List apps via `/home/fana-deploy/fana-deploy list`. Operator must remove an unused app via `/home/fana-deploy/fana-deploy remove <stale_app>` before proceeding. |
