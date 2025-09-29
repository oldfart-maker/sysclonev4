#!/usr/bin/env bash
set -Eeuo pipefail
mf="Makefile"
[[ -f "$mf" ]] || { echo "[patch] ERROR: $mf not found"; exit 1; }
changed=0

append_line_if_missing() { local pat="$1" line="$2";
  if ! grep -Eq "$pat" "$mf"; then printf '%s\n' "$line" >> "$mf"; changed=1; echo "[patch] + $line"; fi; }

append_block_if_missing() { local pat="$1";
  if ! grep -Eq "$pat" "$mf"; then
    cat >>"$mf" <<'BLK'

# ---------- devices quick smoke test ----------
.PHONY: devices-smoke
devices-smoke:
	@echo "[smoke] unmount (quiet)"; \
	  BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)"   ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-unmounted; \
	echo "[smoke] mount"; \
	  BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)"   ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-mounted; \
	echo "[smoke] verify"; \
	  findmnt -nr -o SOURCE,TARGET | grep -E "(/mnt/sysclone-(boot|root))" || true; \
	echo "[smoke] unmount (final)"; \
	  BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)"   ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-unmounted
BLK
    changed=1; echo "[patch] + devices-smoke target"
  fi
}

echo "[patch] updating $mf"
append_line_if_missing '^[[:space:]]*BOOT_MNT[[:space:]]*\?=' 'BOOT_MNT ?= $(BOOT_MOUNT)'
append_line_if_missing '^[[:space:]]*ROOT_MNT[[:space:]]*\?=' 'ROOT_MNT ?= $(ROOT_MOUNT)'
append_block_if_missing '^[[:space:]]*devices-smoke:'

if [[ $changed -eq 0 ]]; then echo "[patch] no changes needed"; else echo "[patch] updated $mf"; fi
