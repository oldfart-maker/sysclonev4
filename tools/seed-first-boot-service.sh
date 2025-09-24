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
[[ -e "$BOOT_PART" ]] && sudo mount "$BOOT_PART" "$BOOT_MOUNT" 2>/dev/null || true
sudo mount "$ROOT_PART" "$ROOT_MOUNT"

log "[install] BOOT=${BOOT_PART:-N/A} mounted at $BOOT_MOUNT"
log "[install] ROOT=$ROOT_PART mounted at $ROOT_MOUNT"

# Install payload + unit
sudo install -Dm755 seeds/layer1/first-boot-provision.sh "$ROOT_MOUNT/usr/local/lib/sysclone/first-boot-provision.sh"
sudo install -Dm644 seeds/layer1/first-boot.service        "$ROOT_MOUNT/etc/systemd/system/sysclone-first-boot.service"

# Ensure Wi-Fi script present on ROOT (copy from BOOT if needed)
if [[ -e "$BOOT_PART" && -f "$BOOT_MOUNT/sysclone-first-boot.sh" ]]; then
  sudo install -Dm755 "$BOOT_MOUNT/sysclone-first-boot.sh" "$ROOT_MOUNT/usr/local/sbin/sysclone-first-boot.sh"
fi

# Enable the unit
sudo mkdir -p "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf ../sysclone-first-boot.service "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants/sysclone-first-boot.service"

sudo umount "$ROOT_MOUNT" || true
[[ -e "$BOOT_PART" ]] && sudo umount "$BOOT_MOUNT" || true
log "[install] done"
