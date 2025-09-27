#!/usr/bin/env bash
set -Eeuo pipefail
log(){ echo "$@"; }

BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"

# Resolve partitions by label (override with DEVICE if passed by your Makefile)
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
log "[install] ROOT=$ROOT_MOUNT mounted at $ROOT_MOUNT"

# Payload + unit
sudo install -Dm755 seeds/layer1/first-boot-provision.sh "$ROOT_MOUNT/usr/local/lib/sysclone/first-boot-provision.sh"
sudo install -Dm644 seeds/layer1/first-boot.service        "$ROOT_MOUNT/etc/systemd/system/sysclone-first-boot.service"

# If a firstboot script was staged on BOOT, copy it into ROOT
if [[ -e "$BOOT_PART" && -f "$BOOT_MOUNT/sysclone-first-boot.sh" ]]; then
  sudo install -Dm755 "$BOOT_MOUNT/sysclone-first-boot.sh" "$ROOT_MOUNT/usr/local/sbin/sysclone-first-boot.sh"
fi

# --- write /etc/sysclone/firstboot.env for first-boot (from Makefile env or ./tools/.env) ---
# shell defaults allow Makefile to pass WIFI_SSID/WIFI_PASS/USERNAME/USERPASS,
# otherwise we also dot-source ./tools/.env if present.
if [[ -f "./tools/.env" ]]; then . "./tools/.env"; fi

sudo install -d -m 0755 "$ROOT_MOUNT/etc/sysclone"
sudo tee "$ROOT_MOUNT/etc/sysclone/firstboot.env" >/dev/null <<EOF
WIFI_SSID='${WIFI_SSID:-}'
WIFI_PASS='${WIFI_PASS:-}'
USERNAME='${USERNAME:-username}'
USERPASS='${USERPASS:-username}'
EOF
sudo chmod 0640 "$ROOT_MOUNT/etc/sysclone/firstboot.env" || true
# ---------------------------------------------------------------------------

# Enable the unit in the target
sudo mkdir -p "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf ../sysclone-first-boot.service "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants/sysclone-first-boot.service"

# Unmount
sudo umount "$ROOT_MOUNT" || true
[[ -e "$BOOT_PART" ]] && sudo umount "$BOOT_MOUNT" || true
log "[install] done"
