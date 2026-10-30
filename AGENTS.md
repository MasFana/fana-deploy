# AGENTS.md — Autonomous Agent Operating Manual

> **Scope**: Master specification and operational index for AI agents (Claude Code, Hermes Agent, Nanobot, OpenClaw, OpenHands, Zed, Cursor) operating on `fana-deploy`.

---

## 1. System Overview & Philosophy

`fana-deploy` is an autonomous deployment and infrastructure orchestrator designed for resource-constrained **Alpine Linux aarch64** virtual machines (1GB–2GB RAM). It delivers zero-downtime atomic deployments for multiple Laravel applications under a strict global FrankenPHP memory ceiling ($\le 250\text{MB}$ idle, $\le 350\text{MB}$ peak).

```
[Public User HTTPS]
        │
        ▼
[Cloudflare Edge] (TLS Termination)
        │  Cloudflare Tunnel (65836ee6-469f-4372-83bb-6d8844dfd338)
        ▼
[cloudflared daemon]
        │
        ├─── Host: skripsi.fmo.qzz.io ────► [127.0.0.1:8080] (Python Viewer - PROTECTED)
        │
        └─── Host: *.fmo.qzz.io ─────────► [127.0.0.1:8088] (FrankenPHP / Caddy)
                                                    │
                                     ┌──────────────┴──────────────┐
                                     ▼                             ▼
                             [app1/current/public]         [app2/current/public]
                             (SQLite WAL: shared/)         (SQLite WAL: shared/)
```

---

## 2. The Golden Rules & Non-Negotiable Invariants

All AI agents executing actions on this host must strictly respect these safety boundaries:

1. **Port 8080 is Untouchable**: `skripsi.fmo.qzz.io` on `127.0.0.1:8080` (Python viewer) must **NEVER** be killed, stopped, or removed from `/etc/cloudflared/config.yml`.
2. **Classic PHP Mode Only**: Applications run using FrankenPHP's `php_server` directive. Never introduce Octane, persistent worker daemons, or FrankenPHP worker mode unless explicit operator consent is documented.
3. **Strict SQLite Storage**: All apps must store state in `/home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite` using `PRAGMA journal_mode=WAL;` and `PRAGMA synchronous=NORMAL;`. Reject MySQL, PostgreSQL, Redis, and Horizon.
4. **Heavy Lock Serialization**: Memory-intensive tasks (Composer install, npm asset builds, database migrations) must run exclusively under `/home/fana-deploy/deployment/run/heavy.lock` using `nice -n 10` and `ionice -c3`. Never run concurrent builds.
5. **Atomic Release Switching**: Releases are housed in `releases/<timestamp>` and activated by atomically updating the `current` symlink. Never build or clone directly into `current`.
6. **Mandatory Post-Deploy Cache Clearing Barrier**: After any code update or symlink swap, always clear Laravel framework caches (`config:clear`, `route:clear`, `view:clear`, `cache:clear`) to prevent HTTP 500 errors.
7. **Capacity Ceiling**: The host supports a maximum of **8 active applications**. Reject any new deployment if capacity is reached until an unused application is decommissioned.

---

## 3. Agent Skills Matrix & Capability Catalog

Detailed documentation for each capability is located under `skills/<skill_name>/SKILL.md`. Machine-readable schema is in `skills/index.json`.

| Skill Identifier | Primary Responsibility | Trigger Phrases / Intent | Core Execution Command | Failure Recovery Action |
| :--- | :--- | :--- | :--- | :--- |
| **`laravel-deploy`** | Deploy or upgrade a Laravel app | "deploy laravel", "update app", "install repository" | `/home/fana-deploy/fana-deploy deploy <git_url> [as <app>] [domain <dom>]` | Inspect `dmesg`, retry once under heavy lock; abort with diagnostic report if OOM persists. |
| **`app-lifecycle`** | Manage app state, logs, rollback, removal | "check status", "view logs", "restart app", "rollback", "remove app", "list apps" | `/home/fana-deploy/fana-deploy <action> <app>` | If rollback fails: check `releases/` history; if restore fails: inspect backup integrity. |
| **`caddy-site`** | Configure and reload FrankenPHP Caddy vhosts | "configure vhost", "validate caddy", "reload frankenphp" | `frankenphp validate --adapter caddyfile --config /home/fana-deploy/deployment/caddy/Caddyfile` | If invalid: remove candidate `.caddy` file, do not reload process, preserve running state. |
| **`cloudflare-tunnel`** | Ingress subdomain routing | "add domain", "remove ingress", "validate tunnel", "check https" | `/usr/bin/python3 /home/fana-deploy/scripts/ingress_tool.py <add\|remove> <hostname>` | If validation fails: automatically revert to `/etc/cloudflared/config.yml.bak`. |
| **`sqlite-ops`** | WAL tuning, backup snapshots, lock mitigation | "migrate db", "database is locked", "backup sqlite", "vacuum db" | `sqlite3 <db_path> 'PRAGMA integrity_check;'` | Restore pre-deploy snapshot from `deployment/backups/<app>/` if corrupted; fix `fana:fana` permissions. |
| **`health-monitor`** | System RAM, swap, disk, OOM audit | "check health", "system status", "memory audit", "check oom" | `/home/fana-deploy/fana-deploy audit` | Alert operator when MemAvailable < 150MB; identify top 3 RSS memory hogs. |

---

## 4. CLI Orchestrator Contract (`fana-deploy`)

Autonomous agents should prioritize using the high-level `fana-deploy` CLI rather than invoking raw shell commands manually:

```bash
/home/fana-deploy/fana-deploy <command> [arguments...]
```

### Command Reference

- **`deploy <git_url> [as <app_name>] [domain <hostname>]`**:
  Clones repo, executes preflight check, verifies `composer.lock`, links shared SQLite and storage, runs locked composer install, conditionally runs npm build, creates pre-deploy database backup, runs locked migrations, runs database seeders (if first deploy), atomically points `current`, clears caches, registers Caddy vhost, validates ingress, configures cron, and updates telemetry registry.
- **`update <app_name>`**:
  Pulls fresh commits for existing app into a new release directory, runs full build/migration pipeline, clears caches, and updates symlink.
- **`rollback <app_name>`**:
  Atomically switches `current` symlink to the previous timestamped release directory in `releases/`, resets opcache, and reloads FrankenPHP.
- **`status [app_name]`**:
  Without arguments: runs health audit and lists all apps.
  With `<app_name>`: shows active release, git commit, SQLite size, origin HTTP status, public HTTPS status, and recent log lines.
- **`logs <app_name>`**:
  Tails the last 50 lines of Caddy access logs or `storage/logs/laravel.log`.
- **`restart <app_name>`**:
  Restarts FrankenPHP under user `fana` with `GOMEMLIMIT=350MiB GOGC=75` and clears PHP opcode cache.
- **`backup <app_name>`**:
  Creates an instant snapshot of `database.sqlite` in `deployment/backups/<app_name>/` and prunes snapshots beyond the 5 most recent.
- **`restore <app_name> <backup_file>`**:
  Restores database from specified snapshot file and resets permissions (`fana:fana 664`).
- **`remove <app_name>`**:
  Creates final archive `final_archive.sqlite`, removes tunnel ingress, removes Caddy site, removes cron entries, deletes app files, and reloads web server.
- **`list`**:
  Tabular overview of active apps, domains, releases, and statuses.
- **`audit`**:
  Executes `scripts/health_check.sh` returning exit code 0 if healthy, 1 if warning/critical.

---

## 5. System Paths Map

```
/home/fana-deploy/
├── fana-deploy                          # Main orchestrator executable
├── config.yml                           # Host configuration (from config.example.yml)
├── deployment/
│   ├── apps/<app_name>/
│   │   ├── current -> releases/<time>   # Active release symlink
│   │   ├── meta.json                    # First deploy & seeding metadata
│   │   ├── releases/<timestamp>/        # Immutable release directories
│   │   └── shared/
│   │       ├── .env                     # Shared environment configuration
│   │       ├── database/database.sqlite # Shared SQLite WAL database
│   │       └── storage/                 # Shared storage (logs, framework cache)
│   ├── backups/<app_name>/              # SQLite snapshot backups (retention: 5)
│   ├── caddy/
│   │   ├── Caddyfile                    # Global FrankenPHP base configuration
│   │   └── sites/<app_name>.caddy       # Per-app virtual host files
│   ├── logs/
│   │   ├── <app_name>.log               # Per-app Caddy access logs
│   │   ├── deploy.log                   # Deployment pipeline execution log
│   │   └── frankenphp.stdout.log        # Web server process log
│   ├── registry.json                    # Telemetry & status cache
│   └── run/
│       ├── heavy.lock                   # Global build & migration serialization lock
│       └── <app_name>.lock              # Per-application deployment lock
├── scripts/
│   ├── health_check.sh                  # Health monitor audit script
│   ├── ingress_tool.py                  # Declarative Cloudflare ingress modifier
│   ├── lock.sh                          # Lock manager (app & heavy)
│   ├── logging.sh                       # Color-coded logging utility
│   ├── preflight.sh                     # Pre-deployment capacity & resource validator
│   ├── rollback.sh                      # Symlink rollback engine
│   └── update_registry.py               # Telemetry generator
└── skills/                              # Machine-readable agent skills
    ├── app-lifecycle/SKILL.md
    ├── caddy-site/SKILL.md
    ├── cloudflare-tunnel/SKILL.md
    ├── health-monitor/SKILL.md
    ├── laravel-deploy/SKILL.md
    └── sqlite-ops/SKILL.md
```

---

## 6. Autonomous Troubleshooting & Decision Trees

### A. OOM Killer Invocations (Exit Code 137)
1. Run `dmesg | tail -n 25` to confirm which PID was killed.
2. Check if a heavy lock was bypassed.
3. Check available memory: `free -h` and `ps -o pid,user,comm,vsz,rss | sort -k5 -rn | head -n 5`.
4. If MemAvailable + SwapFree $< 600\text{MB}$, drop filesystem page cache:
   ```bash
   sync && echo 3 > /proc/sys/vm/drop_caches
   ```
5. Re-run task with heavy lock:
   ```bash
   /home/fana-deploy/scripts/lock.sh heavy env COMPOSER_MEMORY_LIMIT=1G composer install ...
   ```

### B. HTTP 500 View / Route Error
1. Cause: Compiled views or route caches pointing to old release paths.
2. Fix: Run the cache-clearing barrier:
   ```bash
   cd /home/fana-deploy/deployment/apps/<app>/current
   php artisan config:clear
   php artisan route:clear
   php artisan view:clear
   php artisan cache:clear
   ```
3. Restart web server: `/home/fana-deploy/fana-deploy restart <app>`.

### C. SQLite `database is locked` Error
1. Cause: Transaction timeout or WAL mode missing.
2. Fix:
   ```bash
   DB="/home/fana-deploy/deployment/apps/<app>/shared/database/database.sqlite"
   sqlite3 "${DB}" 'PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;'
   chown -R fana:fana "$(dirname "${DB}")"
   chmod 775 "$(dirname "${DB}")"
   chmod 664 "${DB}"*
   ```
3. Check for lingering background artisan workers:
   ```bash
   fuser "${DB}" 2>/dev/null
   ```

### D. Cloudflare Ingress Failure
1. If public HTTPS fails or `cloudflared tunnel ingress validate` errors:
2. Check diff with backup:
   ```bash
   diff -u /etc/cloudflared/config.yml.bak /etc/cloudflared/config.yml
   ```
3. Restore backup:
   ```bash
   cp /etc/cloudflared/config.yml.bak /etc/cloudflared/config.yml
   cloudflared tunnel ingress validate
   /usr/bin/python3 -c "import scripts.ingress_tool as t; t.restart_tunnel()"
   ```

---

## 7. Tool-Specific Integration Adapters

- **Claude Code**: Reads `CLAUDE.md` automatically at repo root. Use `fana-deploy <cmd>` directly.
- **Hermes Agent**: Reads `HERMES.md`, `AGENTS.md`, and individual contracts from `skills/*/SKILL.md`.
- **Nanobot**: Configured via `nanobot.json` with commands pre-bound to orchestrator subcommands.
- **OpenClaw**: Tools declared in `openclaw.json` with JSON schemas and parameter validation.
