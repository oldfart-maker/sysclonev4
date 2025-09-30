#!/usr/bin/env bash
set -euo pipefail
mf=Makefile

# Insert expand-rootfs right after disable-first-boot (if not already there)
if grep -q 'seed-layer1-all:' "$mf"; then
  if ! grep -q 'seed-layer1-expand-rootfs' "$mf"; then
    sed -i '/\$(MAKE) seed-layer1-disable-first-boot; \\/a\ \ \ \ \$(MAKE) seed-layer1-expand-rootfs; \\' "$mf"
    echo "[ok] inserted seed-layer1-expand-rootfs into seed-layer1-all"
  else
    echo "[skip] seed-layer1-expand-rootfs already referenced in seed-layer1-all"
  fi

  # Insert pi-devtools just before ensure-unmounted (if not already there)
  if ! grep -q 'seed-pi-devtools' "$mf"; then
    sed -i '/\$(MAKE) ensure-unmounted; \\/i\ \ \ \ \$(MAKE) seed-pi-devtools; \\' "$mf"
    echo "[ok] inserted seed-pi-devtools into seed-layer1-all"
  else
    echo "[skip] seed-pi-devtools already referenced in seed-layer1-all"
  fi
else
  echo "[err] seed-layer1-all target not found in Makefile" >&2
  exit 1
fi

git add "$mf"
git commit -m "layer1: add expand-rootfs + pi-devtools to seed-layer1-all (minimal edit)" || true
git tag -a v4.6.3-layer1-all-expanded -m "seed-layer1-all includes expand-rootfs and pi-devtools" || true
