---
name: cloudflare-tunnel
category: devops
description: Safe Cloudflare Tunnel ingress management for fana-deploy on tunnel 65836ee6-469f-4372-83bb-6d8844dfd338. Use when registering new subdomains, removing ingress routes, verifying public HTTPS reachability, or recovering from tunnel ingress configuration errors.
version: 1.1.0
tools:
  - python3
  - cloudflared
  - bash
  - curl
---

# Cloudflare Tunnel Skill for fana-deploy

## Scope & Trigger Context
Use this skill whenever:
- Adding a new application subdomain to Cloudflare Tunnel.
- Removing decommissioned domains from `/etc/cloudflared/config.yml`.
- Validating tunnel ingress rules without disrupting active traffic.
- Troubleshooting external domain resolution or tunnel daemon restarts.

## Non-Negotiable Invariants (The Golden Rules)
1. **Existing Service Protection**: The host `skripsi.fmo.qzz.io` pointing to `http://localhost:8080` (Python viewer) must **NEVER** be removed, modified, or impacted.
2. **Strict Ingress Ordering**: All application entries must be inserted **BEFORE** the terminal catch-all rule:
   ```yaml
     - service: http_status:404
   ```
3. **Automated Atomic Validation**: Always validate configuration via `cloudflared tunnel ingress validate` before restarting the tunnel process. If validation fails, automatically revert to `/etc/cloudflared/config.yml.bak`.
4. **Target Destination**: Application services must forward traffic strictly to `http://127.0.0.1:8088`.

## Standard Ingress Format
```yaml
  - hostname: <app>.<domain>
    service: http://127.0.0.1:8088
    originRequest:
      noTLSVerify: true
```

## Deterministic Operations via Ingress Tool

Always perform ingress modifications using the declarative Python utility (`/home/fana-deploy/scripts/ingress_tool.py`), which enforces backups, ordering, and validation atomically:

### 1. Add Domain Ingress
```bash
/usr/bin/python3 /home/fana-deploy/scripts/ingress_tool.py add <domain> [service_url]
# Example:
/usr/bin/python3 /home/fana-deploy/scripts/ingress_tool.py add myapp.fmo.qzz.io http://127.0.0.1:8088

# Register DNS route in Cloudflare (if needed)
cloudflared tunnel route dns 65836ee6-469f-4372-83bb-6d8844dfd338 <domain> 2>/dev/null || true
```

### 2. Remove Domain Ingress
```bash
/usr/bin/python3 /home/fana-deploy/scripts/ingress_tool.py remove <domain>
# Example:
/usr/bin/python3 /home/fana-deploy/scripts/ingress_tool.py remove myapp.fmo.qzz.io
```
*Note: Any attempt to remove `skripsi.fmo.qzz.io` is rejected immediately by the script.*

### 3. Verification & Health Probing
```bash
# 1. Validate ingress structure
cloudflared tunnel ingress validate

# 2. Check tunnel process is running
pgrep -f "cloudflared tunnel"

# 3. Probe public HTTPS endpoint
curl -s -o /dev/null -w "%{http_code}\n" --connect-timeout 5 "https://<domain>/"
```

## Emergency Recovery
If the tunnel configuration becomes corrupted or fails validation:
```bash
# Restore from backup
cp /etc/cloudflared/config.yml.bak /etc/cloudflared/config.yml
cloudflared tunnel ingress validate

# Restart tunnel daemon safely
pkill -9 -f "cloudflared tunnel run" || true
pkill -9 -f "cloudflared.*tunnel run" || true
sleep 1
/opt/skripsi_watchdog.sh
```
