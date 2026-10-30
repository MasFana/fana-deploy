#!/usr/bin/env python3
import os
import json
import glob
import time
import urllib.request
import urllib.error

BASE_DIR = "/home/fana-deploy"
APPS_DIR = os.path.join(BASE_DIR, "deployment/apps")
SITES_DIR = os.path.join(BASE_DIR, "deployment/caddy/sites")
REGISTRY_FILE = os.path.join(BASE_DIR, "deployment/registry.json")

def get_app_domain(app_name):
    site_file = os.path.join(SITES_DIR, f"{app_name}.caddy")
    if not os.path.exists(site_file):
        return None
    try:
        with open(site_file, "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("http://"):
                    dom = line.split()[0].replace("http://", "").replace(":8088", "").replace("{", "").strip()
                    return dom
    except Exception:
        pass
    return None

def check_app_health(domain):
    if not domain:
        return {"status": "unknown", "http_code": 0}
    try:
        req = urllib.request.Request("http://127.0.0.1:8088/", headers={"Host": domain})
        with urllib.request.urlopen(req, timeout=1.5) as resp:
            return {"status": "healthy" if resp.status == 200 else "warning", "http_code": resp.status}
    except urllib.error.HTTPError as e:
        return {"status": "warning" if e.code < 500 else "error", "http_code": e.code}
    except Exception as e:
        return {"status": "down", "http_code": 0, "error": str(e)}

def update():
    apps = []
    if os.path.isdir(APPS_DIR):
        for app_name in sorted(os.listdir(APPS_DIR)):
            app_path = os.path.join(APPS_DIR, app_name)
            if not os.path.isdir(app_path):
                continue
            
            current_sym = os.path.join(app_path, "current")
            release = "none"
            if os.path.islink(current_sym):
                release = os.path.basename(os.readlink(current_sym))
            
            domain = get_app_domain(app_name) or f"{app_name}.fmo.qzz.io"
            db_file = os.path.join(app_path, "shared/database/database.sqlite")
            db_size = "0 B"
            if os.path.exists(db_file):
                size = os.path.getsize(db_file)
                if size < 1024:
                    db_size = f"{size} B"
                elif size < 1024 * 1024:
                    db_size = f"{size/1024:.1f} KB"
                else:
                    db_size = f"{size/(1024*1024):.1f} MB"

            health = check_app_health(domain)
            apps.append({
                "name": app_name,
                "domain": domain,
                "url": f"https://{domain}",
                "release": release,
                "db_size": db_size,
                "health": health["status"],
                "http_code": health["http_code"],
                "last_seen": int(time.time())
            })

    data = {
        "updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "total_apps": len(apps),
        "apps": apps
    }

    os.makedirs(os.path.dirname(REGISTRY_FILE), exist_ok=True)
    temp_file = REGISTRY_FILE + ".tmp"
    with open(temp_file, "w") as f:
        json.dump(data, f, indent=2)
    os.replace(temp_file, REGISTRY_FILE)
    print(f"Registry updated: {len(apps)} app(s) registered.")

if __name__ == "__main__":
    update()
