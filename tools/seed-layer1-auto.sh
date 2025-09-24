#!/usr/bin/env bash
set -Eeuo pipefail

log(){ [[ "${QUIET:-0}" = "1" ]] || echo "$@"; }

BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASS="${WIFI_PASS:-}"

sudo mkdir -p "$BOOT_MOUNT"

# Mount if not already mounted
mounted_here=0
if ! mountpoint -q "$BOOT_MOUNT"; then
  if [[ -e "/dev/disk/by-label/${BOOT_LABEL}" ]]; then
    sudo mount "/dev/disk/by-label/${BOOT_LABEL}" "$BOOT_MOUNT"
    log "[seed] Mounted BOOT by label: ${BOOT_LABEL} -> $BOOT_MOUNT"
    mounted_here=1
  elif [[ -n "${DEVICE:-}" ]]; then
    part="${DEVICE}1"; [[ "$DEVICE" =~ mmcblk|nvme ]] && part="${DEVICE}p1"
    sudo mount "$part" "$BOOT_MOUNT"
    log "[seed] Mounted BOOT by device: $part -> $BOOT_MOUNT"
    mounted_here=1
  else
    echo "[seed] ERROR: could not auto-mount BOOT (FAT/VFAT)."; exit 1
  fi
else
  log "[seed] Using BOOT: $BOOT_MOUNT (pre-mounted:${BOOT_LABEL})"
fi

# Start from the repo copy
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
head -n1 seeds/layer1/first-boot.sh > "$tmp"

# Optional Wi-Fi injection
if [[ -n "$WIFI_SSID" && -n "$WIFI_PASS" ]]; then
  log "[seed] injecting WIFI_SSID/WIFI_PASS into sysclone-first-boot.sh (SSID=${WIFI_SSID})"
  printf 'WIFI_SSID=%q\nWIFI_PASS=%q\n' "$WIFI_SSID" "$WIFI_PASS" >> "$tmp"
fi

# Remainder of script
tail -n +2 seeds/layer1/first-boot.sh >> "$tmp"

# Copy to BOOT without trying to preserve mode/owner/timestamps (VFAT-safe)
sudo cp --remove-destination --no-preserve=mode,ownership,timestamps "$tmp" "$BOOT_MOUNT/sysclone-first-boot.sh"
# chmod on vfat is mostly symbolic; harmless if ignored
sudo chmod 0755 "$BOOT_MOUNT/sysclone-first-boot.sh" || true
sync

# Unmount only if we mounted it here
if [[ "$mounted_here" = "1" ]]; then
  sudo umount "$BOOT_MOUNT" || true
fi
log "[seed] Seed complete."
