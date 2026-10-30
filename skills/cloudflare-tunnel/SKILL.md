---
name: cloudflare-tunnel
category: devops
description: Safe Cloudflare Tunnel ingress management for fana-deploy on existing tunnel.
version: 1.0.0
---

# Cloudflare Tunnel Skill for fana-deploy

## Scope
Safely register subdomains into `/etc/cloudflared/config.yml` for tunnel `65836ee6-469f-4372-83bb-6d8844dfd338`.

## Golden Rules
1. Existing Services Untouchable: `skripsi.fmo.qzz.io` pointing to `http://localhost:8080` must NEVER be modified or broken.
2. Ingress Order: All new app hostnames MUST be placed BEFORE the catch-all `- service: http_status:404`.
3. Validation: ALWAYS run `cloudflared tunnel ingress validate` before restarting tunnel.
4. Origin Target: Forward to `http://127.0.0.1:8088`.

## Ingress Entry Format
```yaml
  - hostname: <app>.<domain>
    service: http://127.0.0.1:8088
    originRequest:
      noTLSVerify: true
```
