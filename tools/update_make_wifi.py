#!/usr/bin/env python3
import re, pathlib, sys

p = pathlib.Path("Makefile")
s = p.read_text()

changed = False

# 1) Ensure WIFI vars exist near the top-level config block and are exported
def ensure_wifi_vars(txt):
    global changed
    if "WIFI_SSID ?=" not in txt and "WIFI_PASS ?=" not in txt:
        # Insert after a known config line like IMG_URL or CACHE_DIR
        anchor = re.search(r'^\s*IMG_URL.*\n', txt, flags=re.M)
        insert_at = anchor.end() if anchor else 0
        block = (
            "\n# ----- Wi-Fi (edit once here; inherited by seeding scripts) -----\n"
            "WIFI_SSID ?=\n"
            "WIFI_PASS ?=\n"
            "export WIFI_SSID\n"
            "export WIFI_PASS\n"
        )
        txt = txt[:insert_at] + block + txt[insert_at:]
        changed = True
    else:
        # Ensure export lines present
        if "export WIFI_SSID" not in txt or "export WIFI_PASS" not in txt:
            txt = txt.replace("WIFI_PASS ?=", "WIFI_PASS ?=\nexport WIFI_SSID\nexport WIFI_PASS")
            changed = True
    return txt

# 2) Update show-config to include masked Wi-Fi (don’t show raw pass)
def ensure_show_config_wifi(txt):
    global changed
    pat = r'^\s*show-config:.*?\n((?:\t.*\n)+)'
    m = re.search(pat, txt, flags=re.M)
    if not m:
        return txt
    block = m.group(1)
    if "WIFI_SSID" in block:
        return txt  # already added
    # add two echo lines before the block ends
    new_block = block
    new_block += '\t@echo "WIFI_SSID = $(WIFI_SSID)"\n'
    new_block += '\t@echo "WIFI_PASS = $$(python3 - <<\'EOS\'\n'
    new_block += 'import os\n'
    new_block += 'pw=os.getenv(\"WIFI_PASS\",\"\")\n'
    new_block += 'print(\"*\"*len(pw) if pw else \"\")\n'
    new_block += 'EOS\n'
    new_block += ')"\n'
    txt = txt.replace(block, new_block)
    changed = True
    return txt

# 3) Clean help text for seed-layer1 (remove the old env hint)
txt = s
txt = ensure_wifi_vars(txt)
txt = ensure_show_config_wifi(txt)
txt = re.sub(r'(seed-layer1:\s*##\s*Auto-mount, seed, unmount).*', r'seed-layer1: ## Auto-mount, seed, unmount', txt)

if txt != s:
    p.write_text(txt)
    print("[update] Makefile updated.")
else:
    print("[update] No changes needed.")
