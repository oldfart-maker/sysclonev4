#!/usr/bin/env bash
set -euo pipefail
mf=Makefile
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

# Add target only if missing
if ! grep -qE '^[[:space:]]*seed-layer1-network-bootstrap:' "$mf"; then
  cat >> "$mf" <<'MK'

# Layer1: bootstrap clock/certs/keyrings/mirrors on first boot (pre-firstboot)
seed-layer1-network-bootstrap: ensure-mounted ## Layer1: stage network/certs bootstrap service
	@echo "[layer1] seed-network-bootstrap"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-layer1-network-bootstrap.sh

.PHONY: seed-layer1-network-bootstrap
MK
fi

# Ensure aggregate includes it before first-boot-service
# Insert after seed-layer1-expand-rootfs; if not found, place before seed-layer1-first-boot-service
if grep -q 'seed-layer1-all:.*' "$mf"; then
  # Only add if not already present
  if ! sed -n '/seed-layer1-all:/,/^[[:alnum:]_-]\+:/p' "$mf" | grep -q 'seed-layer1-network-bootstrap'; then
    # Try to insert after 'seed-layer1-expand-rootfs'
    if sed -n '/seed-layer1-all:/,/^[[:alnum:]_-]\+:/p' "$mf" | grep -q 'seed-layer1-expand-rootfs'; then
      perl -0777 -pe '
        s/(seed-layer1-all:[^\n]*\n[ \t]*@set -euo pipefail;[^\n]*\n[ \t]*\$\([mM]AKE\) seed-layer1-expand-rootfs;[^\n]*\n)/$1          $(MAKE) seed-layer1-network-bootstrap;\n/g
      ' -i "$mf" || true
    else
      perl -0777 -pe '
        s/(seed-layer1-all:[^\n]*\n[ \t]*@set -euo pipefail;[^\n]*\n)/$1          $(MAKE) seed-layer1-network-bootstrap;\n/g
      ' -i "$mf" || true
    fi
  fi
fi

echo "[make-patch] updated $mf (backup at $bak)"
