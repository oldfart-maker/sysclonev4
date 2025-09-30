#!/usr/bin/env bash
set -euo pipefail
mf=Makefile

# 1) Insert the two calls into the existing aggregate (idempotent)
if grep -q '^seed-layer1-all:' "$mf"; then
  # after disable-first-boot → expand-rootfs
  if ! grep -q '\$(MAKE) seed-layer1-expand-rootfs; \\' "$mf"; then
    sed -i '/\$(MAKE) seed-layer1-disable-first-boot; \\/a\ \ \ \ \$(MAKE) seed-layer1-expand-rootfs; \\' "$mf"
    echo "[ok] inserted seed-layer1-expand-rootfs into seed-layer1-all"
  else
    echo "[skip] expand-rootfs already referenced"
  fi
  # before ensure-unmounted → seed-pi-devtools
  if ! grep -q '\$(MAKE) seed-pi-devtools; \\' "$mf"; then
    sed -i '/\$(MAKE) ensure-unmounted; \\/i\ \ \ \ \$(MAKE) seed-pi-devtools; \\' "$mf"
    echo "[ok] inserted seed-pi-devtools into seed-layer1-all"
  else
    echo "[skip] seed-pi-devtools already referenced"
  fi
else
  echo "[err] seed-layer1-all target not found" >&2
  exit 1
fi

# 2) Provide seed-layer1-expand-rootfs if missing (use helper if present)
if ! grep -q '^[[:space:]]*seed-layer1-expand-rootfs[[:space:]]*:' "$mf"; then
  cat >> "$mf" <<'EOF'

# Layer1: stage rootfs expansion for first boot (uses helper if present)
seed-layer1-expand-rootfs: ensure-mounted ## Layer1: stage rootfs grow on first boot
	@set -euo pipefail; \
	  if [ -x tools/seed-expand-rootfs.sh ]; then \
	    echo "[layer1] expand-rootfs via tools/seed-expand-rootfs.sh"; \
	    sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-expand-rootfs.sh; \
	  else \
	    echo "[layer1] WARN: tools/seed-expand-rootfs.sh not found; skipping expansion staging"; \
	  fi

.PHONY: seed-layer1-expand-rootfs
EOF
  echo "[ok] added minimal seed-layer1-expand-rootfs target"
else
  echo "[skip] seed-layer1-expand-rootfs already defined"
fi

git add "$mf"
git commit -m "layer1: wire expand-rootfs + pi-devtools into seed-layer1-all; add minimal expand-rootfs target if missing" || true
git tag -a v4.6.4-layer1-aggregate-fix -m "Fix aggregate & add expand-rootfs stub" || true
