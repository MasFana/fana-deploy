---
name: caddy-site
category: devops
description: Manage Caddy vhost configs for FrankenPHP on origin 127.0.0.1:8088.
version: 1.0.0
---

# Caddy Site Skill

## Scope
Configure, validate, and reload Caddy virtual hosts under `/home/fana-deploy/deployment/caddy/sites/*.caddy`.

## Architecture & Constraints
- Origin: Binds exclusively to `127.0.0.1:8088`.
- Global settings in `Caddyfile`: `admin off`, `auto_https off`, `frankenphp { num_threads 4 max_threads 8 }`.
- Log rotation: `roll_size 10MiB`, `roll_keep 3`.
- Routing: Host matched from incoming Host header forwarded by Cloudflare tunnel.
- Reload: Validate first with `frankenphp validate --adapter caddyfile --config /home/fana-deploy/deployment/caddy/Caddyfile`, then reload with `frankenphp reload` or SIGHUP.

## Site Template
```caddyfile
http://<domain>:8088 {
    bind 127.0.0.1
    root * /home/fana-deploy/deployment/apps/<app>/current/public
    encode zstd gzip
    file_server
    php_server
    log {
        output file /home/fana-deploy/deployment/logs/<app>.log {
            roll_size 10MiB
            roll_keep 3
        }
    }
}
```
