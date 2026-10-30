# fana-deploy

Agent-operated DevOps deployment engine for hosting multiple Laravel applications on resource-constrained Alpine Linux hosts (aarch64 / x86_64). Built on FrankenPHP (Caddy Go web server with embedded PHP SAPI), SQLite WAL mode, and Cloudflare Tunnel edge routing.

---

## Technical Specifications & Resource Budget

Designed to run reliably on Single Board Computers (e.g. RK3588, Cortex-A76/A55) and low-memory VPS instances with 1GB to 2GB total system RAM.

| Metric | Target / Limit | Mechanism |
| :--- | :--- | :--- |
| **FrankenPHP Idle RSS** | $\le$ 250 MB | In-process classic `php_server` worker model (no Octane memory leaks) |
| **Go Runtime Memory Limit** | `GOMEMLIMIT=350MiB` | Forces aggressive GC when memory approaches threshold |
| **Go GC Target Percentage** | `GOGC=75` | Triggers GC cycle when heap grows 75% over live data |
| **FrankenPHP Threads** | `num_threads: 4`, `max_threads: 8` | Prevents thread explosion under burst traffic |
| **Database Memory** | 10–30 MB per app | Embedded SQLite engine in shared storage (eliminates 150MB+ MySQL daemon) |
| **Composer Memory Limit** | `COMPOSER_MEMORY_LIMIT=1G` | Bounded allocation for dependency graph calculation |
| **Frontend Build Limit** | `--max-old-space-size=768` | Caps Node.js heap during Vite/NPM asset compilation |
| **Resource Fencing** | `nice -n 10 ionice -c3` | De-prioritizes CPU/disk IO of build processes behind serving traffic |
| **Build Serialization** | `flock -x -w 600 heavy.lock` | Serializes heavy operations (composer, npm, migrate) system-wide |
| **Multi-Tenant Limit** | 8 active applications | Hard gate in preflight check |

### Memory Budget Math

```
[Total System RAM: 1024 MB - 2048 MB]
  │
  ├── Base OS (Alpine Linux kernel, chrony, sshd, sysctl) : ~60 MB
  ├── Cloudflared Daemon & System Watchdog                  : ~40 MB
  ├── Protected Services (e.g. Viewer on :8080)            : ~30 MB
  ├── FrankenPHP Runtime (Master + Caddy + PHP runtime)    : ~150 - 250 MB RSS (Capped at 350 MB)
  │     ├── Base Heap: ~80 MB
  │     └── Active Request Buffers & Opcache: ~100-150 MB
  └── Heavy Task Allocation (Only one active at a time)     : ~350 - 500 MB (via heavy.lock)
        ├── composer install --no-dev  (peaks ~300 MB)
        └── npm run build              (peaks ~450 MB)
```

---

## Architecture

### Request & Traffic Flow

```
+--------------------+
|  Incoming Request  |
+---------+----------+
          |
          v (Public HTTPS / Edge SSL)
+--------------------+
| Cloudflare Network | (TLS termination, DDoS filtering, HTTP/3)
+---------+----------+
          |
          v (Encrypted outbound tunnel)
+--------------------+
| cloudflared daemon | (/etc/cloudflared/config.yml)
+---------+----------+
          |
          v HTTP Cleartext (127.0.0.1:8088, Host Header preserved)
+--------------------+
| FrankenPHP / Caddy | (Global: admin off, auto_https off)
|                    | (Sites: /deployment/caddy/sites/*.caddy)
+---------+----------+
          |
          v (Classic php_server execution)
+-------------------------------------------------------------+
| /home/fana-deploy/deployment/apps/<app>/current/public     |
|                      index.php                              |
+------------------------------+------------------------------+
                               |
                               v
+-------------------------------------------------------------+
| Storage: /home/fana-deploy/deployment/apps/<app>/shared/   |
|   ├── database/database.sqlite (PRAGMA journal_mode=WAL)    |
|   ├── storage/app, framework, logs                          |
|   └── .env                                                  |
+-------------------------------------------------------------+
```

### Directory Structure

```
/home/fana-deploy/
├── fana-deploy              # CLI orchestrator and entry point
├── config.example.yml       # Configuration blueprint
├── .gitignore               # Ignores runtime state (/deployment/, *.log, *.sqlite)
├── docs/
│   └── architecture.md      # Deep-dive architectural specification
├── scripts/
│   ├── logging.sh           # Formatted timestamp logging to deploy.log
│   ├── lock.sh              # Application lock and global heavy flock wrapper
│   ├── preflight.sh         # Memory, swap, disk capacity, and dependency validator
│   ├── rollback.sh          # Atomic symlink rollback and opcache clear
│   ├── health_check.sh      # Procfs-based system telemetry and service auditor
│   ├── ingress_tool.py      # Declarative parser for /etc/cloudflared/config.yml
│   └── update_registry.py   # State registry compiler (/deployment/registry.json)
├── templates/
│   ├── Caddyfile.base       # Base Caddy reverse-proxy configuration
│   ├── site.caddy           # Template for per-application virtual host blocks
│   ├── ingress.yml          # Template snippet for cloudflared ingress entries
│   └── watchdog.sh          # Origin health poller and automatic restarter
├── skills/                  # Agent tool definitions (Hermes / Claude Code / Nous)
│   ├── laravel-deploy/SKILL.md
│   ├── caddy-site/SKILL.md
│   ├── cloudflare-tunnel/SKILL.md
│   ├── sqlite-ops/SKILL.md
│   ├── app-lifecycle/SKILL.md
│   └── health-monitor/SKILL.md
└── deployment/              # Runtime state directory (git-ignored)
    ├── config.yml           # Active node configuration
    ├── registry.json        # Dynamic status matrix of all deployed apps
    ├── apps/
    │   └── <app>/
    │       ├── current -> releases/<timestamp>
    │       ├── releases/
    │       │   ├── 20261028224012/
    │       │   └── 20261028231540/
    │       ├── shared/
    │       │   ├── .env
    │       │   ├── database/database.sqlite
    │       │   └── storage/
    │       └── meta.json
    ├── caddy/
    │   ├── Caddyfile
    │   └── sites/
    │       └── <app>.caddy
    ├── backups/
    │   └── <app>/
    │       └── db_predeploy_<timestamp>.sqlite
    ├── logs/
    │   ├── deploy.log
    │   ├── caddy.log
    │   ├── frankenphp.stdout.log
    │   └── <app>.log
    └── run/
        ├── heavy.lock
        └── <app>.lock
```

---

## Agent-Based DevOps Interface

This platform implements an agentic contract. AI agents (Claude Code, Hermes Agent, Nanobot, OpenClaw, OpenHands, Zed, Cursor) execute operations through structured declarations in `/home/fana-deploy/skills/` and agent index files:

- **`AGENTS.md`**: Master agent operating manual and skills index for all AI coding and DevOps agents.
- **`CLAUDE.md`**: Native Claude Code instructions, command cheat sheet, and safety invariants.
- **`HERMES.md`**: Nous Research Hermes Agent runtime guidelines and capability map.
- **`openclaw.json`**: OpenClaw tool manifest with JSON schemas and parameter contracts.
- **`nanobot.json`**: Nanobot configuration mapping intents to orchestrator actions.
- **`skills/index.json`**: Machine-readable JSON index of all skills with execution parameters.

### How Skills Function

Each skill directory contains a `SKILL.md` document conforming to the Agent Skill Standard (YAML frontmatter + strict operational rules). The AI agent parses the skill, verifies pre-conditions, enforces constraints, runs deterministic tool commands, and executes post-condition validations.

| Skill | Operational Scope | Guardrails & Invariants |
| :--- | :--- | :--- |
| **`laravel-deploy`** | Clones repo, validates `composer.lock`, executes fenced dependencies, migrates DB, seeds initial data, atomically swaps symlink, and purges Laravel cache. | Enforces SQLite only; rejects Redis/Horizon/Octane packages unless overridden; runs builds under `heavy.lock` with `nice -n 10 ionice -c3`; auto-clears `config`, `route`, `view`, and `cache` to prevent HTTP 500 errors. |
| **`caddy-site`** | Generates vhost configs under `/deployment/caddy/sites/<app>.caddy` and triggers server reload. | Validates syntax with `frankenphp validate` prior to process reload; strictly binds to `127.0.0.1:8088`; log file rotation (`roll_size 10MiB`, `roll_keep 3`). |
| **`cloudflare-tunnel`** | Ingress routing manipulation via `scripts/ingress_tool.py`. | **Protected Service Rule:** `skripsi.fmo.qzz.io` on port 8080 is immutable; inserts hostnames before catch-all `- service: http_status:404`; runs `cloudflared tunnel ingress validate` before restart; verifies public HTTPS code. |
| **`sqlite-ops`** | Maintenance of SQLite databases in `shared/database/database.sqlite`. | Enforces `PRAGMA journal_mode=WAL` and `PRAGMA synchronous=NORMAL`; automatic pre-migration snapshot to `/deployment/backups/<app>/`; automated 5-snapshot retention pruning; fixes permissions to `chmod 664 fana:fana`. |
| **`app-lifecycle`** | Status queries, atomic updates, symlink rollbacks, database backup/restore, application pruning, and decommissioning. | Enforces 8-app system cap; retains 3 latest release directories and 5 database backups; writes final database archive (`final_archive.sqlite`) on application deletion. |
| **`health-monitor`** | Zero-overhead `/proc` telemetry and process tree auditing. | Reads `/proc/meminfo` and `/proc/uptime` directly (no Python/Node daemon overhead); alerts on `MemAvailable < 150MB`, `Swap > 70%`, `Disk > 85%`, or kernel OOM killer events in `dmesg`; ranks top RSS processes. |

---

## CLI Reference

The primary binary is `/home/fana-deploy/fana-deploy`.

```bash
# Deploy a repository
fana-deploy deploy <git_url> [as <app_name>] [domain <hostname>]

# Update existing app (re-fetches git remote, builds new release, runs migrations, swaps symlink)
fana-deploy update <app_name>

# Instant atomic rollback to previous release
fana-deploy rollback <app_name>

# Inspect app details (release ID, git commit, DB size, origin HTTP code, public HTTPS code)
fana-deploy status <app_name>

# Inspect host system health (RAM, swap, disk, core services, top RSS processes)
fana-deploy status

# View runtime and access logs
fana-deploy logs <app_name>

# Restart FrankenPHP runtime and invalidate opcache
fana-deploy restart [app_name]

# Create manual snapshot of SQLite database
fana-deploy backup <app_name>

# Restore database from snapshot file
fana-deploy restore <app_name> <path_to_backup.sqlite>

# Remove application (creates final DB archive, unlinks ingress, deletes files)
fana-deploy remove <app_name>

# List all deployed applications and active domains
fana-deploy list

# Run system health check and exit with non-zero on alert
fana-deploy audit
```

### CLI Command Execution Details

#### 1. `deploy`
```bash
./fana-deploy deploy https://github.com/example/laravel-app.git as myapp domain myapp.fmo.qzz.io
```
1. Executes `scripts/preflight.sh` (validates memory $\ge 600\text{MB}$ RAM+swap, free disk $\ge 1.5\text{GB}$, app count $< 8$).
2. Acquires per-app lock: `deployment/run/myapp.lock`.
3. Creates directory tree: `deployment/apps/myapp/{releases,shared/database,shared/storage}`.
4. Performs shallow git clone: `git clone --depth 1 <url> releases/<timestamp>`.
5. Preflight check inside repository: verifies `composer.lock` exists and rejects blacklisted dependencies (`predis`, `laravel/horizon`, `laravel/octane`).
6. Configures `.env` with SQLite driver, random `APP_KEY`, and links `shared/.env` and `shared/storage`.
7. Acquires `heavy.lock`: runs `COMPOSER_MEMORY_LIMIT=1G composer install --no-dev --prefer-dist --optimize-autoloader`.
8. Frontend build: if `public/build` exists in git, skips npm; otherwise executes `NODE_OPTIONS=--max-old-space-size=768 npm ci && npm run build` and deletes `node_modules`.
9. Copies `database.sqlite` to `deployment/backups/myapp/db_predeploy_<timestamp>.sqlite`.
10. Runs database migrations: `php artisan migrate --force`.
11. If first deployment and seeder exists, runs `php artisan db:seed --force`.
12. Atomically flips symlink: `ln -sfn releases/<timestamp> current`.
13. Purges caches: `php artisan config:clear && route:clear && view:clear && cache:clear`.
14. Creates vhost in `deployment/caddy/sites/myapp.caddy` and reloads FrankenPHP.
15. Injects ingress block into `/etc/cloudflared/config.yml` via `ingress_tool.py` and syncs Cloudflare DNS route.
16. Adds minutely scheduler cron: `php artisan schedule:run`.
17. Prunes release directories (keeps 3) and database backups (keeps 5).
18. Refreshes `/home/fana-deploy/deployment/registry.json`.

---

## Installation & Setup

### Prerequisites (Alpine Linux)

```bash
# 1. Install base dependencies and PHP 8.4 packages
apk add bash curl git sqlite jq util-linux python3 \
    php84 php84-fpm php84-phar php84-iconv php84-openssl \
    php84-mbstring php84-xml php84-curl php84-zip php84-gd \
    php84-intl php84-bcmath php84-pdo_sqlite php84-opcache \
    php84-tokenizer php84-dom php84-fileinfo php84-sqlite3 \
    php84-session composer nodejs npm

# 2. Install FrankenPHP binary
curl -sSL https://frankenphp.dev/install.sh | sh
mv frankenphp /usr/local/bin/

# 3. Create non-root runtime user
adduser -D -u 1000 fana

# 4. Install Cloudflared
# Download cloudflared aarch64 / amd64 binary to /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
```

### Initial Node Configuration

```bash
cd /home/fana-deploy
mkdir -p deployment/caddy/sites deployment/apps deployment/backups deployment/logs deployment/run

# Copy base configuration
cp config.example.yml deployment/config.yml
cp templates/Caddyfile.base deployment/caddy/Caddyfile

# Set ownership
chown -R fana:fana deployment
chmod 755 fana-deploy
```

### Starting the Web Server

Start FrankenPHP under `fana` user using configured memory limits:

```bash
su -s /bin/bash fana -c \
  "GOMEMLIMIT=350MiB GOGC=75 nohup /usr/local/bin/frankenphp run \
   --config /home/fana-deploy/deployment/caddy/Caddyfile \
   --adapter caddyfile >> /home/fana-deploy/deployment/logs/frankenphp.stdout.log 2>&1 &"
```

To automate process monitoring, add `templates/watchdog.sh` to root cron:
```cron
* * * * * /home/fana-deploy/templates/watchdog.sh > /dev/null 2>&1
```

---

## Operational Runbook & Troubleshooting

### 1. Build Failure: Out of Memory (Exit Code 137)
- **Symptom**: Composer or npm terminated abruptly with exit code 137.
- **Root Cause**: Linux kernel OOM killer terminated the process.
- **Verification**: Run `dmesg -T | grep -E -i "oom[-_]killer|out of memory"`.
- **Resolution**:
  1. Check free memory: `free -m`.
  2. Verify swap space is enabled ($\ge 1\text{GB}$ recommended on 1GB RAM systems): `swapon --show`.
  3. Verify no concurrent heavy tasks are running: `cat /home/fana-deploy/deployment/run/heavy.lock`.
  4. Ensure assets are compiled before pushing to git (`public/build` committed), allowing deployment to bypass `npm run build`.

### 2. HTTP 500: View Not Found / Route Not Found
- **Symptom**: Application returns HTTP 500 immediately following a new release.
- **Root Cause**: Laravel cached outdated paths from previous release directory in `bootstrap/cache/routes-v7.php` or `config.php`.
- **Resolution**:
  ```bash
  cd /home/fana-deploy/deployment/apps/<app>/current
  php artisan config:clear
  php artisan route:clear
  php artisan view:clear
  php artisan cache:clear
  /home/fana-deploy/fana-deploy restart
  ```

### 3. Database Locked (`SQLSTATE[HY000]: General error: 5 database is locked`)
- **Symptom**: Concurrent writes fail during traffic bursts or scheduled jobs.
- **Root Cause**: SQLite file missing WAL journal mode or write timeout too short.
- **Verification**:
  ```bash
  sqlite3 /home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite "PRAGMA journal_mode;"
  # Output must be: wal
  ```
- **Resolution**:
  ```bash
  sqlite3 /home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite "PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;"
  chmod 664 /home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite*
  chown fana:fana /home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite*
  ```

### 4. Cloudflare Ingress Corruption
- **Symptom**: Tunnel fails to route traffic or `cloudflared` fails to reload.
- **Resolution**:
  1. Check config validity: `cloudflared tunnel ingress validate`.
  2. If corrupted, restore backup: `cp /etc/cloudflared/config.yml.bak /etc/cloudflared/config.yml`.
  3. Validate again: `cloudflared tunnel ingress validate`.
  4. Restart tunnel: `pkill -9 -f "cloudflared tunnel run" && /opt/skripsi_watchdog.sh`.

### 5. Immediate Release Rollback
- **Execution**:
  ```bash
  /home/fana-deploy/fana-deploy rollback <app>
  ```
  If schema changes broke the previous release, restore pre-deploy SQLite snapshot:
  ```bash
  /home/fana-deploy/fana-deploy restore <app> /home/fana-deploy/deployment/backups/<app>/db_predeploy_<previous_timestamp>.sqlite
  ```
