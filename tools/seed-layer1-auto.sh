#!/usr/bin/env bash
set -Eeuo pipefail

log(){ [[ "${QUIET:-0}" = "1" ]] || echo "$@"; }

BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASS="${WIFI_PASS:-}"

sudo mkdir -p "$BOOT_MOUNT"

# Mount if not already mounted
if ! mountpoint -q "$BOOT_MOUNT"; then
  if [[ -e "/dev/disk/by-label/${BOOT_LABEL}" ]]; then
    sudo mount "/dev/disk/by-label/${BOOT_LABEL}" "$BOOT_MOUNT"
    log "[seed] Mounted BOOT by label: ${BOOT_LABEL} -> $BOOT_MOUNT"
  elif [[ -n "${DEVICE:-}" ]]; then
    part="${DEVICE}1"; [[ "$DEVICE" =~ mmcblk|nvme ]] && part="${DEVICE}p1"
    sudo mount "$part" "$BOOT_MOUNT"
    log "[seed] Mounted BOOT by device: $part -> $BOOT_MOUNT"
  else
    echo "[seed] ERROR: could not auto-mount BOOT (FAT/VFAT)."; exit 1
  fi
else
  log "[seed] Using BOOT: $BOOT_MOUNT (pre-mounted:${BOOT_LABEL})"
fi

# Copy the script (sudo because BOOT is root-owned)
sudo install -Dm755 seeds/layer1/first-boot.sh "$BOOT_MOUNT/sysclone-first-boot.sh"

# Optional Wi-Fi injection (write as root)
if [[ -n "$WIFI_SSID" && -n "$WIFI_PASS" ]]; then
  log "[seed] injecting WIFI_SSID/WIFI_PASS into sysclone-first-boot.sh (SSID=${WIFI_SSID})"
  tmp="$(mktemp)"
  head -n1 seeds/layer1/first-boot.sh > "$tmp"
  printf 'WIFI_SSID=%q\nWIFI_PASS=%q\n' "$WIFI_SSID" "$WIFI_PASS" >> "$tmp"
  tail -n +2 seeds/layer1/first-boot.sh >> "$tmp"
  sudo mv -f "$tmp" "$BOOT_MOUNT/sysclone-first-boot.sh"
  sudo chmod 0755 "$BOOT_MOUNT/sysclone-first-boot.sh"
fi

# Flush and unmount if we mounted it here
sync
if mount | grep -q " on $BOOT_MOUNT "; then
  sudo umount "$BOOT_MOUNT" || true
fi
log "[seed] Seed complete."
