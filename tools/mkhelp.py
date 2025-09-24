#!/usr/bin/env python3
import re, sys, pathlib, os
mf = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "Makefile").read_text()

# Parse "target: ## description"
rows = []
for line in mf.splitlines():
    m = re.match(r'^([A-Za-z0-9_.-]+):.*##\s*(.+)', line)
    if m:
        rows.append((m.group(1), m.group(2)))

# Param hints per target (central, easy to edit)
PARAMS = {
  "img-download": [
    "IMG_URL (Makefile) — image URL"
  ],
  "img-unpack": [
    "none"
  ],
  "sd-write": [
    "DEVICE=/dev/sdX (required)",
    "CONFIRM=yes (required)"
  ],
  "flash-all": [
    "DEVICE=/dev/sdX (required)",
    "CONFIRM=yes (required)"
  ],
  "seed-disable-firstboot": [
    "ROOT_PART=/dev/disk/by-label/ROOT_MNJRO (recommended)",
    "BOOT_PART=/dev/disk/by-label/BOOT_MNJRO (recommended)",
    "or DEVICE=/dev/sdX (optional fallback)"
  ],
  "seed-layer1": [
    "WIFI_SSID / WIFI_PASS (from Makefile)"
  ],
  "seed-first-boot-service": [
    "ROOT_PART=/dev/disk/by-label/ROOT_MNJRO (recommended)",
    "BOOT_PART=/dev/disk/by-label/BOOT_MNJRO (recommended)",
    "or DEVICE=/dev/sdX (optional fallback)"
  ],
  "seed-all": [
    "ROOT_PART=/dev/disk/by-label/ROOT_MNJRO (recommended)",
    "BOOT_PART=/dev/disk/by-label/BOOT_MNJRO (recommended)",
    "WIFI_SSID / WIFI_PASS (from Makefile)",
    "or DEVICE=/dev/sdX (optional fallback)"
  ],
  "show-config": [
    "none"
  ],
  "tag": [
    "VERSION=vX.Y.Z (required)"
  ],
  "version-bump": [
    "VERSION=vX.Y.Z (required)"
  ],
}

# Optional: detail view if TARGET=name is passed from make
detail = os.environ.get("TARGET") or (sys.argv[2] if len(sys.argv) > 2 else "")

# Print table
print("Targets:")
w = max((len(t) for t,_ in rows), default=8) + 2
for t, d in sorted(rows, key=lambda x: x[0]):
    print(f"  {t.ljust(w)}- {d}")

if detail:
    print(f"\nParams for '{detail}':")
    hints = PARAMS.get(detail, [])
    if not hints:
        print("  (none documented)")
    else:
        for h in hints:
            print(f"  - {h}")
else:
    print("\nTip: show params for one target →  make help TARGET=<name>")
