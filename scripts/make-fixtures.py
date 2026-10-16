#!/usr/bin/env python3
"""Build anonymized SentinelCore test fixtures from real UniFi API responses.

Input is the folder written by the local API test scripts (not in the repo):
    1-sites.json, 2-stat-device.json, log30/page-*.json

Usage: scripts/make-fixtures.py ~/Downloads/unifi-api-test

Every IP, MAC, object ID, client name, Wi-Fi name and admin name is replaced with
a stable fake value, so the same real value always maps to the same fake one.
"""
import glob
import json
import os
import re
import sys

SRC = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/Downloads/unifi-api-test")
OUT = os.path.join(os.path.dirname(__file__), "..", "SentinelCore", "Tests", "SentinelCoreTests", "Fixtures")

IPV4 = re.compile(r"\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b")
MAC = re.compile(r"\b[0-9a-fA-F]{2}(?::[0-9a-fA-F]{2}){5}\b")
OBJECT_ID = re.compile(r"\b[0-9a-f]{24}\b")
UUID = re.compile(r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b")

maps = {"ip": {}, "mac": {}, "oid": {}, "uuid": {}, "name": {}}


def fake_ip(m):
    real = m.group(0)
    if real not in maps["ip"]:
        a = int(m.group(1))
        b = int(m.group(2))
        private = a == 10 or (a == 192 and b == 168) or (a == 172 and 16 <= b <= 31)
        pool = [k for k, v in maps["ip"].items() if v.startswith("10.20." if private else "203.0.113.")]
        n = len(pool) + 1
        maps["ip"][real] = f"10.20.{n // 250}.{n % 250 + 1}" if private else f"203.0.113.{n}"
    return maps["ip"][real]


def fake(kind, real, fmt):
    table = maps[kind]
    if real not in table:
        table[real] = fmt(len(table) + 1)
    return table[real]


def scrub_str(s):
    s = UUID.sub(lambda m: fake("uuid", m.group(0), lambda n: f"00000000-0000-4000-8000-{n:012d}"), s)
    s = OBJECT_ID.sub(lambda m: fake("oid", m.group(0), lambda n: f"{n:024x}"), s)
    s = MAC.sub(lambda m: fake("mac", m.group(0).lower(), lambda n: f"02:00:00:00:{n // 256:02x}:{n % 256:02x}"), s)
    return IPV4.sub(fake_ip, s)


def scrub(value):
    if isinstance(value, dict):
        return {k: scrub(v) for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if isinstance(value, str):
        return scrub_str(value)
    return value


PRIVATE_NAME_PARAMS = {"CLIENT": "Client", "SRC_CLIENT": "Client", "DST_CLIENT": "Client",
                       "ADMIN": "Admin", "WLAN": "HomeWiFi", "NETWORK": "LAN",
                       "OBJECT": "Object", "SETTING_NAME": "Setting"}


def scrub_entry(entry):
    params = entry.get("parameters", {})
    for key, label in PRIVATE_NAME_PARAMS.items():
        p = params.get(key)
        if not p:
            continue
        for field in ("name", "hostname", "display_property_value"):
            if field in p:
                p[field] = fake("name", f"{label}:{p[field]}", lambda n, label=label: f"{label} {n}")
    return scrub(entry)


def load_api(path):
    text = open(path).read().rsplit("\nHTTP", 1)[0]
    return json.loads(text)


def write(name, data):
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("wrote", name)


# --- system log -------------------------------------------------------------
rows = []
for path in sorted(glob.glob(os.path.join(SRC, "log30", "page-*.json"))):
    rows += json.load(open(path))["data"]
rows.sort(key=lambda r: r["timestamp"], reverse=True)

watched = [r for r in rows if r["category"] in ("INTERNET_AND_WAN", "SECURITY")
           and r["key"] != "BACKUP_CONNECTION_IN_USE"]
noise_seen = {}
noise = []
for r in rows:
    if r["category"] in ("CLIENT_DEVICES", "AUDIT", "SOFTWARE_UPDATES") and noise_seen.get(r["key"], 0) < 3:
        noise_seen[r["key"]] = noise_seen.get(r["key"], 0) + 1
        noise.append(r)
picked = sorted(watched + noise, key=lambda r: r["timestamp"], reverse=True)
picked = [scrub_entry(r) for r in picked]

half = (len(picked) + 1) // 2
for page, chunk in enumerate((picked[:half], picked[half:])):
    write(f"system-log-page{page}.json", {
        "page_number": page,
        "total_element_count": len(picked),
        "total_page_count": 2,
        "data": chunk,
    })
write("system-log-empty.json", {"page_number": 0, "total_element_count": 0, "total_page_count": 0, "data": []})

# --- stat/device (gateway only, relevant fields only) -----------------------
devices = load_api(os.path.join(SRC, "2-stat-device.json"))["data"]
gateway = next(d for d in devices if d.get("type") in ("udm", "ugw", "uxg"))
WAN_FIELDS = ("name", "ifname", "up", "enable", "ip", "port_idx", "media", "speed", "full_duplex", "is_uplink")
keep = {k: gateway[k] for k in ("_id", "mac", "ip", "name", "model", "type", "version",
                                 "last_wan_status", "last_wan_interfaces", "state") if k in gateway}
keep["wan1"] = {k: gateway["wan1"][k] for k in WAN_FIELDS if k in gateway["wan1"]}
keep = scrub(keep)
write("stat-device.json", {"meta": {"rc": "ok"}, "data": [keep]})

# Same gateway with WAN2 assigned as a failover backup that is up (made up from WAN1).
dual = json.loads(json.dumps(keep))
dual["wan2"] = dict(dual["wan1"], ifname="eth8", name="eth8", port_idx=9, media="GE", speed=1000, ip="203.0.113.200", is_uplink=False)
dual["last_wan_status"] = {"WAN": "online", "WAN2": "online"}
dual["last_wan_interfaces"] = {"WAN": dual["last_wan_interfaces"]["WAN"], "WAN2": {"ip": "203.0.113.200", "alive": True}}
write("stat-device-wan2.json", {"meta": {"rc": "ok"}, "data": [dual]})

# --- integration/v1/sites ---------------------------------------------------
write("sites.json", scrub(load_api(os.path.join(SRC, "1-sites.json"))))

# --- error bodies seen during testing ---------------------------------------
write("error-401.json", {"error": {"code": 401, "message": "Unauthorized"}})
write("error-404.json", {"meta": {"rc": "error", "msg": "api.err.NotFound"}, "data": []})
