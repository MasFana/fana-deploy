# Architectural Specification

This document details the architectural design, memory management model, storage layout, concurrency fences, ingress pipelines, and agentic interface contracts for `fana-deploy`.

---

## 1. System Topology & Traffic Pipeline

`fana-deploy` operates as an isolated single-node deployment system tailored for low-memory Linux hosts (specifically Alpine Linux on aarch64 and x86_64).

```
                      INTERNET
                         │
                         ▼
             ┌───────────────────────┐
             │   Cloudflare Edge     │
             │  - Anycast Network    │
             │  - TLS Termination    │
             │  - DDoS Mitigation    │
             │  - HTTP/2 & HTTP/3    │
             └───────────┬───────────┘
                         │
                         │ (Encrypted WireGuard/QUIC Tunnel)
                         ▼
             ┌───────────────────────┐
             │   cloudflared Daemon  │
             │  (/etc/cloudflared)   │
             └───────────┬───────────┘
                         │
                         │ HTTP Cleartext Loopback (127.0.0.1:8088)
                         │ (Host Header: <app>.<domain>)
                         ▼
             ┌────────────────────────────────────────────────────────┐
             │         FrankenPHP Master Process (PID: fana)          │
             │  - Embedded Caddy v2 Server Engine                     │
             │  - GOMEMLIMIT=350MiB, GOGC=75                          │
             │  - Config: /home/fana-deploy/deployment/caddy/Caddyfile│
             │  - Sites:  deployment/caddy/sites/*.caddy              │
             └───────────┬────────────────────────────────────────────┘
                         │
                         │ (In-process PHP SAPI / php_server)
                         ▼
             ┌────────────────────────────────────────────────────────┐
             │       Laravel Application (Current Release)            │
             │  - /deployment/apps/<app>/current/public/index.php     │
             │  - Shared SQLite WAL Database Connection               │
             └────────────────────────────────────────────────────────┘
```

### Security & Ingress Invariants

1. **Loopback-Only Origin**: FrankenPHP binds exclusively to `127.0.0.1:8088`. No application ports are directly exposed to the public Internet.
2. **Edge TLS Termination**: All public traffic arrives through Cloudflare Tunnel. Local origin configuration operates in plain HTTP (`auto_https off` in Caddyfile), offloading SSL handshake computation and certificate renewal from the local CPU.
3. **Admin API Disabled**: Caddy's administrative API is disabled (`admin off`) to eliminate internal port exposure and eliminate remote attack vectors.
4. **Service Isolation**: Non-deploy services (e.g. internal viewers on port 8080) are permanently protected in `scripts/ingress_tool.py`. Modification of these entries results in an immediate operation abort.

---

## 2. Memory Model & Resource Fencing

### The 1GB–2GB RAM Ceiling Problem

Standard PHP setups running PHP-FPM and MariaDB/MySQL quickly exhaust memory on small SBCs:
- MariaDB base footprint: ~150MB to 300MB idle RSS.
- PHP-FPM master + 4 pool workers: ~120MB to 250MB idle RSS.
- Caddy / Nginx: ~30MB.
Total idle baseline often exceeds 500MB before serving requests. Under concurrent traffic or package builds, memory spikes trigger Linux `oom-killer`, killing arbitrary processes.

### FrankenPHP Memory Control Mechanics

FrankenPHP embeds the PHP SAPI directly inside the Caddy Go binary. Memory consumption is regulated at the Go runtime layer:

1. **`GOMEMLIMIT=350MiB`**:
   The Go 1.19+ soft memory limit sets a strict threshold for the Go runtime heap. When memory approaches 350MiB:
   - The Go garbage collector runs proportionally more aggressively.
   - Inactive memory pages are promptly released back to the Linux kernel via `madvise(..., MADV_DONTNEED)`.
   - Prevents FrankenPHP from crossing cgroup or kernel OOM limits.

2. **`GOGC=75`**:
   Lowers the default target percentage (default is 100). The runtime triggers garbage collection when the heap grows by 75% over reachable data, keeping total RSS consistently below 250MB under steady workloads.

3. **Thread Pool Limits**:
   Configured in `Caddyfile.base`:
   ```caddyfile
   frankenphp {
       num_threads 4
       max_threads 8
   }
   ```
   Restricts the number of active OS threads allocated to the PHP engine. Prevents thread bloat on multi-core ARM chips, containing thread stack overhead ($\approx 8\text{MB}$ per thread on standard glibc, $\approx 128\text{KB}$ on musl libc).

### Resource Fencing: CPU & I/O Priority

Heavy operations (Composer package installation, npm/Vite builds, and SQLite migrations) can starve serving requests of CPU time and disk I/O.

All heavy tasks are executed through `/home/fana-deploy/scripts/lock.sh heavy`:
```bash
flock -x -w 600 /home/fana-deploy/deployment/run/heavy.lock \
    nice -n 10 \
    ionice -c3 \
    "$@"
```
- **`nice -n 10`**: Assigns a high niceness value, granting the process lower scheduling priority than the FrankenPHP serving process.
- **`ionice -c3`**: Sets the Linux I/O scheduling class to "Idle". Disk I/O is granted only when the storage controller has no pending I/O requests from higher-priority processes.
- **`flock -x -w 600`**: Global mutex. Completely serializes build operations across all applications on the host, guaranteeing that two deployments never compile assets or run Composer concurrently.

---

## 3. Storage Architecture & Atomic Deployments

### Application Directory Layout

Every application deployed to `/home/fana-deploy/deployment/apps/<app>` uses an atomic release directory structure:

```
/home/fana-deploy/deployment/apps/<app>/
│
├── current -> /home/fana-deploy/deployment/apps/<app>/releases/20261028231540
│
├── releases/
│   ├── 20261028224012/       # Old release (kept for rollback)
│   └── 20261028231540/       # Active release
│       ├── app/
│       ├── bootstrap/
│       ├── public/
│       │   └── index.php
│       ├── .env -> ../../shared/.env
│       ├── database/
│       │   └── database.sqlite -> ../../../shared/database/database.sqlite
│       └── storage -> ../../shared/storage
│
├── shared/
│   ├── .env
│   ├── database/
│   │   ├── database.sqlite
│   │   ├── database.sqlite-wal
│   │   └── database.sqlite-shm
│   └── storage/
│       ├── app/
│       ├── framework/
│       │   ├── cache/data/
│       │   ├── sessions/
│       │   └── views/
│       └── logs/
│
└── meta.json                 # Deployment metadata (seeded status, initial timestamp)
```

### Atomic Symlink Mechanics

Deployments build the entire target directory (`releases/<timestamp>`) completely before touching the active release pointer:
1. Clones repository to `releases/<timestamp>`.
2. Resolves shared symlinks (`.env`, `storage`, `database.sqlite`).
3. Executes Composer install and asset compilation.
4. Executes database migrations.
5. Swaps symlink atomically:
   ```bash
   ln -sfn "/home/fana-deploy/deployment/apps/<app>/releases/<timestamp>" \
          "/home/fana-deploy/deployment/apps/<app>/current"
   ```
   On POSIX filesystems, `ln -sfn` executes an atomic directory symlink replacement via `rename()`, ensuring no window of time where `/current` is missing or unlinked.

### Cache Build Barrier

Caches must be built for the release that is live, not cleared after it. Following the symlink swap the pipeline runs:

```bash
php artisan optimize        # config, events, routes, views
```

Two failure modes make the old "purge everything" advice actively harmful here:

1. **Stale route cache, not stale cache files**, is what returns HTTP 500/404 after a deploy: a `bootstrap/cache/routes-v7.php` written before a route was added keeps that route invisible (404, or 419 for POST/PATCH behind CSRF). Rebuild with `php artisan route:clear && php artisan optimize`.
2. **`optimize:clear` can deadlock** when `CACHE_STORE` or `SESSION_DRIVER` is the database: the clear writes to the SQLite file that the live FrankenPHP worker is also writing, and the command hangs until killed. Use the `file` cache/session stores, and only clear with the app stopped.

Code-only changes need no cache action at all: with opcache `validate_timestamps=1` and `revalidate_freq=2`, edited PHP files are revalidated within ~2 seconds.

### SQLite WAL Mode Architecture

To eliminate the memory overhead of a dedicated relational database server, `fana-deploy` configures SQLite for multi-tenant concurrent read/write throughput:

1. **WAL Initialization**:
   ```sql
   PRAGMA journal_mode=WAL;
   PRAGMA synchronous=NORMAL;
   ```
2. **Concurrency Profile**:
   - In WAL mode, writes append to `database.sqlite-wal` while reads read from the main database file and the WAL index (`database.sqlite-shm`).
   - Readers never block writers, and writers never block readers.
   - `synchronous=NORMAL` reduces disk `fsync` calls during transactions while preserving WAL crash resilience.
3. **Permissions**:
   All database files and directories are maintained with mode `664` and ownership `fana:fana` to ensure FrankenPHP workers can read and write without privilege elevation.

---

## 4. Ingress Configuration & Tunnel Lifecycle

Public routing is managed via Cloudflare Tunnel configuration in `/etc/cloudflared/config.yml`.

### Declarative Ingress Modification (`ingress_tool.py`)

Direct regex editing of YAML risks structural corruption. `scripts/ingress_tool.py` manages ingress entries deterministically:

1. **Pre-modification Backup**: Automatically creates `/etc/cloudflared/config.yml.bak`.
2. **Ordering Guarantee**: Ingress rules are strictly ordered. All application hostname blocks are injected *before* the mandatory catch-all:
   ```yaml
     - service: http_status:404
   ```
3. **Validation Gate**: Before the tunnel daemon is restarted, the script runs:
   ```bash
   cloudflared tunnel ingress validate
   ```
   If validation exits with a non-zero status, the script restores the `.bak` file and aborts without terminating active tunnels.
4. **Daemon Refresh**: On successful validation, `ingress_tool.py` terminates active tunnel instances and triggers the external watchdog script (`/opt/skripsi_watchdog.sh`) to establish a clean tunnel connection without ghost sockets.
5. **Edge Verification**: The script executes an active verification loop checking `https://<domain>/` over public HTTPS to confirm routing propagation before declaring deployment success.

---

## 5. Agent-Based DevOps Interface & Skill Contracts

`fana-deploy` is designed to be operated autonomously by LLM-based AI agents (Hermes Agent, Claude Code, Nous, OpenHands) as well as human operators.

### Skill Standard Architecture

Each skill under `/home/fana-deploy/skills/` defines a machine-readable operational contract via `SKILL.md`:
- **Frontmatter**: Defines skill name, category, version, and description used for tool matching.
- **Scope & Triggers**: Explicit criteria determining when the agent must load the skill.
- **Constraints & Invariants**: Rules that cannot be bypassed (e.g. SQLite only, no MySQL, port 8080 protection).
- **Execution Workflow**: Deterministic bash commands and verification steps.

```
       ┌────────────────────────────────────────────────────────┐
       │                   Autonomous Agent                     │
       │     (Evaluates Task: "Deploy repository X as Y")       │
       └───────────────────────────┬────────────────────────────┘
                                   │
                                   ▼
       ┌────────────────────────────────────────────────────────┐
       │             Skill Discovery & Contract Load            │
       │           /home/fana-deploy/skills/laravel-deploy      │
       └───────────────────────────┬────────────────────────────┘
                                   │
              ┌────────────────────┴────────────────────┐
              ▼                                         ▼
   [Pre-Condition Checks]                     [Enforce Constraints]
   - Is memory >= 600MB?                     - SQLite driver only
   - Is disk >= 1.5GB?                       - composer.lock required
   - App count < 8?                          - Bounded heap limits
              │                                         │
              └────────────────────┬────────────────────┘
                                   │
                                   ▼
       ┌────────────────────────────────────────────────────────┐
       │              Deterministic Tool Execution              │
       │      fana-deploy deploy <url> as <app> domain <host>   │
       └───────────────────────────┬────────────────────────────┘
                                   │
                                   ▼
       ┌────────────────────────────────────────────────────────┐
       │              Post-Condition Verification               │
       │      - HTTP 200 via origin:8088                        │
       │      - HTTP 200 via public HTTPS                       │
       │      - Update /deployment/registry.json                │
       └────────────────────────────────────────────────────────┘
```

### Tool Contract Summary

| Skill | Input Contract | Verification / Post-Condition | Failure Mode Handling |
| :--- | :--- | :--- | :--- |
| `laravel-deploy` | `git_url`, `app_name`, `domain` | Loopback `curl` returning HTTP 200/302, registry updated | If exit 137: inspect dmesg, retry once under heavy lock; abort with diagnostic output. |
| `caddy-site` | `app_name`, `domain` | `frankenphp validate` returns exit code 0 | If validation fails: remove `.caddy` file, restore previous config, do not reload process. |
| `cloudflare-tunnel`| `hostname`, `service_target` | `cloudflared tunnel ingress validate` returns 0; public HTTPS check succeeds | If validation fails: revert to `/etc/cloudflared/config.yml.bak`. |
| `sqlite-ops` | `app_name`, target operation | Database file exists, `journal_mode=wal`, valid file integrity check | On corruption: restore newest pre-deploy snapshot from `deployment/backups/<app>/`. |
| `app-lifecycle` | `app_name`, target state | Desired release symlinked, old directories pruned to retention limits | On failed update: invoke `fana-deploy rollback <app>`. |
| `health-monitor` | None | MemAvailable $\ge 150\text{MB}$, Swap $\le 70\%$, Disk $\le 85\%$ | Trigger alerts; output top 3 memory-consuming PIDs. |

---

## 6. Telemetry & Monitoring Architecture

System metrics are gathered via direct kernel `/proc` filesystem parsing to avoid the CPU and memory overhead of monitoring daemons (e.g. Prometheus Node Exporter):

1. **Memory Telemetry**: Parsed directly from `/proc/meminfo`:
   - `MemAvailable`: Instantaneous estimate of memory available for starting new applications without swapping.
   - `SwapTotal` & `SwapFree`: Calculates percentage of active swap utilization.
2. **OOM Event Detection**: Reads Linux kernel ring buffer via `dmesg`, correlating timestamp against `/proc/uptime` to flag OOM killer invocations occurring within the last 1800 seconds.
3. **Application State Matrix (`registry.json`)**:
   Maintained automatically by `scripts/update_registry.py` after every deployment, update, or removal event. Output structure:
   ```json
   {
     "updated_at": "2026-10-30T09:30:00Z",
     "total_apps": 2,
     "apps": [
       {
         "name": "myapp",
         "domain": "myapp.fmo.qzz.io",
         "url": "https://myapp.fmo.qzz.io",
         "release": "20261028231540",
         "db_size": "240.0 KB",
         "health": "healthy",
         "http_code": 200,
         "last_seen": 1793352600
       }
     ]
   }
   ```
4. **Watchdog Service (`templates/watchdog.sh`)**:
   Polls `http://127.0.0.1:8088/` every minute. If FrankenPHP fails to respond within 2 seconds:
   - Terminates hanging FrankenPHP processes via `pkill -9`.
   - Re-launches FrankenPHP under user `fana` with `GOMEMLIMIT=350MiB` and `GOGC=75`.
   - Logs event to `deployment/logs/watchdog.log`.
