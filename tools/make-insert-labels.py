#!/usr/bin/env python3
import re, pathlib
p = pathlib.Path("Makefile"); s = p.read_text()

# 1) Ensure BOOT_LABEL/ROOT_LABEL defaults exist near config and are exported
if "BOOT_LABEL ?=" not in s and "ROOT_LABEL ?=" not in s:
    anchor = re.search(r'^\s*CACHE_DIR\s*\?=.*\n', s, flags=re.M)
    ins = (
        "\n# ----- Partition labels (distro defaults; override only if image changes) -----\n"
        "BOOT_LABEL ?= BOOT_MNJRO\n"
        "ROOT_LABEL ?= ROOT_MNJRO\n"
        "export BOOT_LABEL\n"
        "export ROOT_LABEL\n"
    )
    if anchor:
        s = s[:anchor.end()] + ins + s[anchor.end():]
    else:
        s = ins + s

# 2) Make sure show-config prints them (once)
show = re.search(r'^\s*show-config:.*?(?=^\S.*:|\Z)', s, flags=re.M|re.S)
if show and "BOOT_LABEL" not in show.group(0):
    block = show.group(0)
    lines = block.rstrip("\n").splitlines()
    insert_at = 1 + max(i for i,l in enumerate(lines) if "BOOT_MOUNT" in l) if any("BOOT_MOUNT" in l for l in lines) else len(lines)
    lines.insert(insert_at, '\t@echo "BOOT_LABEL = $(BOOT_LABEL)"')
    lines.insert(insert_at+1, '\t@echo "ROOT_LABEL = $(ROOT_LABEL)"')
    s = s.replace(block, "\n".join(lines)+"\n")

p.write_text(s)
print("[update] Makefile: added BOOT_LABEL/ROOT_LABEL and show-config entries.")
