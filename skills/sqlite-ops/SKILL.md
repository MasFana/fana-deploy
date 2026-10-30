---
name: sqlite-ops
category: devops
description: Safe SQLite database maintenance, atomic migrations, WAL mode configuration, backup snapshots, integrity validation, and lock recovery for Laravel applications. Use when running migrations, troubleshooting database locked errors (SQLSTATE HY000: 5), checking SQLite file integrity, creating backups, or vacuuming database files.
version: 1.1.0
tools:
  - sqlite3
  - php
  - bash
---

# SQLite Operations Skill

## Scope & Trigger Context
Use this skill whenever:
- Running database migrations or database seeders under heavy serialization locks.
- Configuring high-concurrency PRAGMA modes on SQLite for web workloads (WAL mode).
- Investigating database concurrency locks (`SQLSTATE[HY000]: General error: 5 database is locked`).
- Creating pre-deployment snapshots or restoring historical database states.
- Running integrity checks (`PRAGMA integrity_check;`) and VACUUM maintenance.

## Standard Database File Location
Database file:
`/home/fana-deploy/deployment/apps/<app_name>/shared/database/database.sqlite`

Related WAL & SHM shared memory files:
- `database.sqlite-wal`
- `database.sqlite-shm`

## Mandatory Operational Standards

### 1. Mandatory PRAGMA Invariants
All SQLite databases must run with:
```sql
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;
PRAGMA busy_timeout=5000;
```
- **WAL (Write-Ahead Logging)** allows concurrent readers and a single writer without blocking web queries.
- **busy_timeout=5000** ensures transactions wait up to 5 seconds before returning a lock error.

### 2. File Permissions & Ownership
Database files and their parent directories must always be accessible to user `fana`:
```bash
DB_DIR="/home/fana-deploy/deployment/apps/<app_name>/shared/database"
chown -R fana:fana "${DB_DIR}"
chmod 775 "${DB_DIR}"
chmod 664 "${DB_DIR}/database.sqlite"
[ -f "${DB_DIR}/database.sqlite-wal" ] && chmod 664 "${DB_DIR}/database.sqlite-wal"
[ -f "${DB_DIR}/database.sqlite-shm" ] && chmod 664 "${DB_DIR}/database.sqlite-shm"
```

### 3. Pre-Migration Backup Snapshot
Before running any migration, always take an atomic backup snapshot:
```bash
BACKUP_DIR="/home/fana-deploy/deployment/backups/<app_name>"
mkdir -p "${BACKUP_DIR}"
DB_FILE="/home/fana-deploy/deployment/apps/<app_name>/shared/database/database.sqlite"

# Use online sqlite3 backup API if available, or direct cp when quiet
sqlite3 "${DB_FILE}" ".backup '${BACKUP_DIR}/db_predeploy_$(date +%Y%m%d%H%M%S).sqlite'"
```
Keep the 5 most recent backups per app and prune older entries.

### 4. Running Migrations Under Heavy Lock
Never run `artisan migrate` directly without acquiring the global heavy lock:
```bash
/home/fana-deploy/scripts/lock.sh heavy php /home/fana-deploy/deployment/apps/<app_name>/current/artisan migrate --force
```

### 5. Integrity Check & Diagnostics
```bash
# Verify SQLite B-Tree and page integrity
sqlite3 "${DB_FILE}" 'PRAGMA integrity_check;'
# Expected output: "ok"

# Verify foreign keys
sqlite3 "${DB_FILE}" 'PRAGMA foreign_key_check;'
```

### 6. Resolving Database Locks (`database is locked`)
If an application encounters `SQLSTATE[HY000]: General error: 5 database is locked`:
1. Check if journal mode is WAL:
   ```bash
   sqlite3 "${DB_FILE}" 'PRAGMA journal_mode;'
   ```
   If not `wal`, set it immediately:
   ```bash
   sqlite3 "${DB_FILE}" 'PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;'
   ```
2. Verify file permissions: Ensure user `fana` has write access to the `.sqlite` file and the parent directory (`shared/database`).
3. Check for hung artisan or background CLI processes locking the database:
   ```bash
   fuser "${DB_FILE}" 2>/dev/null || lsof "${DB_FILE}" 2>/dev/null
   ```
4. Check busy timeout in `.env`:
   Ensure `DB_FOREIGN_KEYS=true` and database config has sufficient timeout in Laravel configuration.
