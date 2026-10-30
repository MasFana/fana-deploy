---
name: sqlite-ops
category: devops
description: Safe SQLite database maintenance, migrations, backup, and optimization for Laravel apps.
version: 1.0.0
---

# SQLite Operations Skill

## Scope
Manage SQLite databases located in `/home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite`.

## Standard Operations
1. Pre-migration backup: Always copy `database.sqlite` to `/home/fana-deploy/deployment/backups/<app>/db_<timestamp>.sqlite` before executing `php artisan migrate --force`.
2. Retention: Keep up to 5 newest backups per app. Prune older backups.
3. Optimization: Run PRAGMA journal_mode=WAL, PRAGMA synchronous=NORMAL, and periodic VACUUM.
4. Permissions: Ensure database file and directory are owned by `fana:fana` with `chmod 664`.
