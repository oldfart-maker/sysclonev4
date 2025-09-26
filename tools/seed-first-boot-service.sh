#!/usr/bin/env bash
set -Eeuo pipefail
log(){ [[ "${QUIET:-0}" = "1" ]] || echo "$@"; }

BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"

# Resolve partitions: default by-label from Makefile, override with DEVICE if provided
if [[ -n "${DEVICE:-}" ]]; then
  if [[ "$DEVICE" =~ mmcblk|nvme ]]; then BOOT_PART="${DEVICE}p1"; ROOT_PART="${DEVICE}p2"; else BOOT_PART="${DEVICE}1"; ROOT_PART="${DEVICE}2"; fi
else
  BOOT_PART="/dev/disk/by-label/${BOOT_LABEL}"
  ROOT_PART="/dev/disk/by-label/${ROOT_LABEL}"
fi

sudo mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"
log "[install] done"

# Unmount only after everything is staged

# --- write /etc/sysclone/firstboot.env for first-boot ---
# allow local values from tools/.env if present
if [ -f "./tools/.env" ]; then . "./tools/.env"; fi
sudo install -d -m 0755 "$ROOT_MOUNT/etc/sysclone"
sudo bash -c 'cat > "$ROOT_MOUNT/etc/sysclone/firstboot.env"' <<EOF
WIFI_SSID=${WIFI_SSID:-}
WIFI_PASS=${WIFI_PASS:-}
USERNAME=${USERNAME:-username}
USERPASS=${USERPASS:-username}
EOF
sudo chmod 0640 "$ROOT_MOUNT/etc/sysclone/firstboot.env" || true
# --------------------------------------------------------

sudo umount "$ROOT_MOUNT" || true
[[ -e "$BOOT_PART" ]] && sudo umount "$BOOT_MOUNT" || true

