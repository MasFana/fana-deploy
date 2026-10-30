#!/usr/bin/env python3
"""
Safely manage ingress rules in /etc/cloudflared/config.yml.
Always keeps skripsi viewer on 8080 untouched.
Always validates with 'cloudflared tunnel ingress validate'.
"""
import sys, re, shutil, subprocess, pathlib, time

CONFIG_PATH = pathlib.Path("/etc/cloudflared/config.yml")
BACKUP_PATH = pathlib.Path("/etc/cloudflared/config.yml.bak")

def validate():
    res = subprocess.run(["cloudflared", "tunnel", "ingress", "validate"], capture_output=True, text=True)
    return res.returncode == 0

def restart_tunnel():
    subprocess.run(["pkill", "-9", "-f", "cloudflared tunnel run"], capture_output=True)
    subprocess.run(["pkill", "-9", "-f", "cloudflared.*tunnel run"], capture_output=True)
    time.sleep(1)
    subprocess.run(["/opt/skripsi_watchdog.sh"], capture_output=True)

def verify_public_https(hostname, max_retries=10, delay=2):
    url = f"https://{hostname}/"
    print(f"Verifying public HTTPS for {url}...")
    for i in range(1, max_retries + 1):
        try:
            res = subprocess.run(
                ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "--connect-timeout", "3", "--max-time", "5", url],
                capture_output=True,
                text=True
            )
            code = res.stdout.strip()
            if code in ["200", "301", "302", "401", "403"]:
                print(f"Public HTTPS verification PASSED for {hostname} (HTTP {code}).")
                return True
            print(f"[{i}/{max_retries}] {hostname} responded with HTTP {code}. Retrying in {delay}s...")
        except Exception as e:
            print(f"[{i}/{max_retries}] Request error: {e}. Retrying in {delay}s...")
        time.sleep(delay)
    print(f"WARNING: Public HTTPS verification failed for {hostname} after {max_retries} attempts.", file=sys.stderr)
    return False

def add_hostname(hostname, service="http://127.0.0.1:8088"):
    if not CONFIG_PATH.exists():
        print(f"Error: {CONFIG_PATH} does not exist", file=sys.stderr)
        return False
    
    content = CONFIG_PATH.read_text()
    if f"hostname: {hostname}" in content:
        print(f"Hostname {hostname} already present in ingress rules.")
        return True

    shutil.copyfile(CONFIG_PATH, BACKUP_PATH)
    
    new_entry = (
        f"  - hostname: {hostname}\n"
        f"    service: {service}\n"
        f"    originRequest:\n"
        f"      noTLSVerify: true\n"
    )

    pattern = r"(\n\s*-\s*service:\s*http_status:404)"
    if not re.search(pattern, content):
        print("Error: Could not locate catch-all http_status:404 in config", file=sys.stderr)
        return False
    
    updated_content = re.sub(pattern, "\n" + new_entry + r"\1", content, count=1)
    CONFIG_PATH.write_text(updated_content)

    if validate():
        print(f"Ingress for {hostname} added and validated successfully.")
        restart_tunnel()
        verify_public_https(hostname)
        return True
    else:
        print(f"Validation failed after adding {hostname}. Rolling back config...", file=sys.stderr)
        shutil.copyfile(BACKUP_PATH, CONFIG_PATH)
        return False

def remove_hostname(hostname):
    if hostname == "skripsi.fmo.qzz.io":
        print("Error: Protecting skripsi.fmo.qzz.io! Removal forbidden.", file=sys.stderr)
        return False

    if not CONFIG_PATH.exists():
        return True

    content = CONFIG_PATH.read_text()
    if f"hostname: {hostname}" not in content:
        print(f"Hostname {hostname} not found in ingress rules.")
        return True

    shutil.copyfile(CONFIG_PATH, BACKUP_PATH)

    # Match the block for this hostname up to next ingress entry
    pattern = rf"\n\s*-\s*hostname:\s*{re.escape(hostname)}[\s\S]*?(?=\n\s*-\s*(?:hostname|service):|\Z)"
    updated_content = re.sub(pattern, "", content, count=1)
    CONFIG_PATH.write_text(updated_content)

    if validate():
        print(f"Ingress for {hostname} removed and validated successfully.")
        restart_tunnel()
        return True
    else:
        print(f"Validation failed after removing {hostname}. Rolling back config...", file=sys.stderr)
        shutil.copyfile(BACKUP_PATH, CONFIG_PATH)
        return False

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: ingress_tool.py <add|remove> <hostname> [service]")
        sys.exit(1)
    cmd = sys.argv[1]
    host = sys.argv[2]
    svc = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:8088"
    if cmd == "add":
        ok = add_hostname(host, svc)
    elif cmd == "remove":
        ok = remove_hostname(host)
    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)
    sys.exit(0 if ok else 1)
