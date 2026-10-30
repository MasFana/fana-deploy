---
name: laravel-deploy
category: devops
description: Deploy Laravel apps on Alpine aarch64 with atomic releases, SQLite, and low-memory limits.
version: 1.0.0
---

# Laravel Deploy Skill

## Trigger & Scope
Use when deploying or upgrading Laravel applications on Alpine Linux aarch64 under strict RAM constraints (<=250MB FrankenPHP target).

## Constraints
- Classic mode: `php_server` only. No Octane / FrankenPHP worker by default.
- SQLite only: Reject MySQL/Postgres/Redis/Horizon/Octane unless operator explicitly permits.
- Global heavy lock: Composer, npm, and migrations run under `/home/fana-deploy/deployment/run/heavy.lock` with `nice -n 10` and `ionice -c3`.
- Composer flags: `COMPOSER_MEMORY_LIMIT=1G composer install --no-dev --prefer-dist --optimize-autoloader --no-interaction`. Never composer update. Require composer.lock. On exit 137 (OOM), check `dmesg | tail`, report, retry once.
- **PHP version**: Verify PHP version matches composer.lock requirements. Laravel 13+ requires PHP 8.4+. Install `php84` + extensions (iconv, openssl, phar, mbstring, xml, curl, zip, gd, intl, bcmath, pdo_sqlite, opcache, tokenizer, dom, fileinfo, sqlite3, session) before composer install.
- Frontend build: If `public/build` exists in repo, SKIP npm. Else run `NODE_OPTIONS=--max-old-space-size=768 npm install && npm run build` under heavy lock (use `npm install` when no package-lock.json; `npm ci` requires lockfile). Always purge `node_modules` after build.
- Queue & Cron: No persistent worker daemon. Schedule `php artisan schedule:run` every minute. If `QUEUE_CONNECTION=database`, run `php artisan queue:work --stop-when-empty --max-time=50` via cron.
- Release retention: Keep 3 newest releases in `/home/fana-deploy/deployment/apps/<app>/releases/`.

## Directory Layout
```
/home/fana-deploy/deployment/apps/<app>/
  ├── current -> releases/<timestamp>
  ├── releases/
  │   └── <timestamp>/
  └── shared/
      ├── .env
      ├── database/database.sqlite
      └── storage/
```

## 6. Post-Deploy Cache Clearing (Critical)
After any code update (`git pull`, `git reset --hard`, new release symlink), **always clear Laravel caches** and verify endpoint health before finishing:
```bash
cd /home/fana-deploy/deployment/apps/<app>/releases/<latest>
php artisan config:clear
php artisan route:clear
php artisan view:clear
php artisan cache:clear
```
**Verification & Trouble Handling**:
- Probe origin & public URL: `curl -I http://127.0.0.1:8088/` (with Host header) and public endpoints.
- If HTTP 500 occurs: check `./fana-deploy logs <app>` or `shared/storage/logs/`, ensure no stale compiled view/route artifacts remain, clear caches again, and restart if needed (`./fana-deploy restart <app>`).
