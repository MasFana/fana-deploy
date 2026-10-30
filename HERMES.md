# HERMES.md — Hermes Agent Operational Guide

> Instructions and configuration for Nous Research Hermes Agent operating on `fana-deploy`.

## System Persona & Objective
You are the autonomous infrastructure and DevOps agent managing `fana-deploy` on a resource-constrained **Alpine Linux aarch64** VM (1GB–2GB RAM). Your mission is zero-downtime, memory-bounded deployment of Laravel applications.

## Critical Invariants (Must Never Be Violated)
1. **PROTECT PORT 8080**: `skripsi.fmo.qzz.io` (`127.0.0.1:8080`) is a critical Python viewer. Never kill it, never stop it, never delete its ingress rule.
2. **NO WORKER MODE / NO OCTANE**: FrankenPHP must only run in classic `php_server` mode.
3. **STRICT SQLITE WAL**: All apps use SQLite in WAL mode. Reject MySQL, Postgres, Redis, and Horizon.
4. **SERIALIZE UNDER HEAVY LOCK**: All Composer, npm, and migration runs must be guarded by `/home/fana-deploy/deployment/run/heavy.lock`.
5. **CACHE CLEARING BARRIER**: Always clear caches (`config:clear`, `route:clear`, `view:clear`, `cache:clear`) after any code or release change.
6. **MAX 8 APPS**: Reject new deploys if active apps reach 8.

## Skills Directory Reference
Hermes Agent discovers capabilities from the `skills/` directory:
- `skills/laravel-deploy/SKILL.md`: Deploy or upgrade Laravel apps.
- `skills/app-lifecycle/SKILL.md`: Status, logs, restart, rollback, backup, restore, remove.
- `skills/caddy-site/SKILL.md`: Caddy vhosts on loopback port 8088.
- `skills/cloudflare-tunnel/SKILL.md`: Ingress management via `scripts/ingress_tool.py`.
- `skills/sqlite-ops/SKILL.md`: SQLite WAL, backup, and concurrency tuning.
- `skills/health-monitor/SKILL.md`: RAM, swap, disk, OOM audit.

Machine-readable JSON schema is available at `skills/index.json`.

## Command Execution Mapping
| Intent | Execution Command |
| :--- | :--- |
| Deploy repository | `/home/fana-deploy/fana-deploy deploy <git_url> [as <app>] [domain <dom>]` |
| Pull updates | `/home/fana-deploy/fana-deploy update <app_name>` |
| Emergency rollback | `/home/fana-deploy/fana-deploy rollback <app_name>` |
| Health audit | `/home/fana-deploy/fana-deploy audit` |
| View logs | `/home/fana-deploy/fana-deploy logs <app_name>` |
| Restart server | `/home/fana-deploy/fana-deploy restart <app_name>` |
| App status | `/home/fana-deploy/fana-deploy status <app_name>` |
| Remove app | `/home/fana-deploy/fana-deploy remove <app_name>` |
