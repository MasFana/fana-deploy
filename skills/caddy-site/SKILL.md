---
name: caddy-site
category: devops
description: Manage Caddy vhost configurations for FrankenPHP on origin 127.0.0.1:8088. Use when configuring new virtual hosts, inspecting Caddy routing, troubleshooting HTTP 502/404 web server issues, or validating Caddyfile configuration syntax without downtime.
version: 1.1.0
tools:
  - frankenphp
  - caddy
  - bash
  - curl
---

# Caddy Site Skill

## Scope & Trigger Context
Use this skill whenever:
- Generating or updating Caddy virtual host definitions for an application.
- Validating Caddyfile syntax before reloading the web server.
- Verifying local loopback proxying on port 8088 with HTTP Host headers.
- Troubleshooting web server routing, TLS termination, or FrankePHP execution.

## Architectural Constraints
- **Origin Binding**: FrankenPHP binds strictly to loopback `127.0.0.1:8088`. Public TLS termination is handled upstream by Cloudflare Tunnel.
- **Global Settings** (`/home/fana-deploy/deployment/caddy/Caddyfile`):
  - `admin off`: Prevents unbounded memory growth from internal administrative state.
  - `auto_https off`: TLS certificates are terminated at Cloudflare edge; Caddy serves plain HTTP to the tunnel.
  - `frankenphp { num_threads 4 max_threads 8 }`: Bounded thread pool prevents memory runaway on aarch64.
- **Log Rotation**: Every site specifies log rotation (`roll_size 10MiB`, `roll_keep 3`) to prevent disk exhaustion.
- **Header Forwarding**: Host header matching routes incoming requests to the appropriate public web root.

## Virtual Host Template
Individual site configurations are stored at:
`/home/fana-deploy/deployment/caddy/sites/<app_name>.caddy`

```caddyfile
http://<domain> {
    bind 127.0.0.1
    root * /home/fana-deploy/deployment/apps/<app_name>/current/public
    encode zstd gzip
    file_server
    php_server
    log {
        output file /home/fana-deploy/deployment/logs/<app_name>.log {
            roll_size 10MiB
            roll_keep 3
        }
    }
}
```

## Validation & Reload Workflow

### 1. Validate Syntax Before Reloading
Always validate before restarting or reloading FrankenPHP:
```bash
su -s /bin/bash fana -c "frankenphp validate --adapter caddyfile --config /home/fana-deploy/deployment/caddy/Caddyfile"
```
If validation returns non-zero, **do not reload**. Immediately inspect stderr and remove or correct the invalid `.caddy` file.

### 2. Reload or Restart FrankenPHP
```bash
# Restart via orchestrator with memory ceilings (GOMEMLIMIT=350MiB GOGC=75)
/home/fana-deploy/fana-deploy restart <app_name>

# Or trigger configuration reload via SIGHUP
pkill -HUP -f "frankenphp run" 2>/dev/null || true
```

### 3. Verify Local Loopback
```bash
# Test base health endpoint
curl -s http://127.0.0.1:8088/
# Expected: "fana-deploy frankenphp online"

# Test specific virtual host
curl -s -o /dev/null -w "%{http_code}\n" -H "Host: <domain>" http://127.0.0.1:8088/
# Expected: 200, 301, or 302
```
