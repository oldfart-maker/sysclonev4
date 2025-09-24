#!/usr/bin/env python3
import re, pathlib
p = pathlib.Path("Makefile")
s = p.read_text()

# Ensure WIFI vars are exported (keep what you already set)
if "export WIFI_SSID" not in s or "export WIFI_PASS" not in s:
    s = s.replace("WIFI_PASS ?=", "WIFI_PASS ?=\nexport WIFI_SSID\nexport WIFI_PASS")

# Replace the whole show-config target with a simple, tab-prefixed version
show_re = re.compile(r'^\s*show-config:.*?(?=^\S.*:|\Z)', re.S | re.M)
new_show = (
    "show-config:  ## Show important variables\n"
    "\t@echo \"IMG_URL    = $(IMG_URL)\"\n"
    "\t@echo \"CACHE_DIR  = $(CACHE_DIR)\"\n"
    "\t@echo \"IMG_XZ     = $(IMG_XZ)\"\n"
    "\t@echo \"IMG_RAW    = $(IMG_RAW)\"\n"
    "\t@echo \"DEVICE     = $(DEVICE)\"\n"
    "\t@echo \"BOOT_MOUNT = $(BOOT_MOUNT)\"\n"
    "\t@echo \"WIFI_SSID  = $(WIFI_SSID)\"\n"
    "\t@echo \"WIFI_PASS  = $(if $(strip $(WIFI_PASS)),(set),(unset))\"\n"
)
if show_re.search(s):
    s = show_re.sub(new_show, s)
else:
    # If not found, append it at the end
    s = s.rstrip() + "\n\n" + new_show + "\n"

p.write_text(s)
print("[fix] show-config rewritten without heredocs; WIFI_* exported.")
