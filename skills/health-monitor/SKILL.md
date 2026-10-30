---
name: health-monitor
category: devops
description: Monitor system RAM, swap, disk, OOM events, and process health without disturbing core services.
version: 1.0.0
---

# Health Monitor Skill

## Scope
Continuous and on-demand health auditing for Alpine Linux aarch64 host.

## Thresholds & Alerts
- MemAvailable < 150MB -> Critical Alert
- Swap used > 70% -> Warning Alert
- Root disk used > 85% -> Warning Alert
- dmesg OOM killer invocations -> Critical Alert
- Alert payload must include top 3 RAM-consuming processes.

## Service Protection Policy
Under NO circumstances kill or interrupt:
- Skripsi viewer on port 8080 (python3)
- Cloudflared tunnel daemon
- Monitoring / watchdog scripts

## On-Demand RAM Check (Alpine/BusyBox)

**Working commands:**
```bash
# Top processes by RSS (memory) - BusyBox top
# -m flag sorts by memory, -b batch mode, -n1 single iteration
top -b -n1 -m | head -20

# Alternative using ps + sort (BusyBox ps doesn't support --sort)
ps aux | sort -k4 -nr | head -20

# System memory summary
free -h
cat /proc/meminfo | head -10
```

**Output parsing:** `top -b -n1 -m` shows columns: PID, VSZ, VSZRW, RSS, SHR, DIRTY, STACK, COMMAND. RSS is resident set size (physical RAM used).