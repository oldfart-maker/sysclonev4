#!/usr/bin/env bash
log(){ [[ "${QUIET:-0}" = "1" ]] || echo "$@"; }
set -Eeuo pipefail

BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"

# Select partitions (prefer explicit by-label paths)
if [[ -n "${ROOT_PART:-}" ]]; then
  : # use ROOT_PART/BOOT_PART as provided
elif [[ -n "${DEVICE:-}" ]]; then
  if [[ "$DEVICE" =~ mmcblk|nvme ]]; then
    BOOT_PART="${DEVICE}p1"; ROOT_PART="${DEVICE}p2"
  else
    BOOT_PART="${DEVICE}1";  ROOT_PART="${DEVICE}2"
  fi
else
  BOOT_PART="$(lsblk -pno NAME,LABEL | awk '$2=="BOOT_MNJRO"||$2=="BOOT"{print $1; exit}')"
  ROOT_PART="$(lsblk -pno NAME,LABEL | awk '$2=="ROOT_MNJRO"||$2=="rootfs"{print $1; exit}')"
fi

[[ -n "${ROOT_PART:-}" ]] || { echo "[install] ERROR: cannot determine ROOT_PART"; exit 1; }

sudo mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"
[[ -n "${BOOT_PART:-}" ]] && sudo mount "$BOOT_PART" "$BOOT_MOUNT" 2>/dev/null || true
sudo mount "$ROOT_PART" "$ROOT_MOUNT"

echo "[install] BOOT=${BOOT_PART:-N/A} mounted at $BOOT_MOUNT"
echo "[install] ROOT=$ROOT_PART mounted at $ROOT_MOUNT"

# Copy provisioning script & unit into ROOT
sudo install -Dm755 seeds/layer1/first-boot-provision.sh "$ROOT_MOUNT/usr/local/lib/sysclone/first-boot-provision.sh"
sudo install -Dm644 seeds/layer1/first-boot.service        "$ROOT_MOUNT/etc/systemd/system/sysclone-first-boot.service"

# Ensure the Wi-Fi script is on ROOT (copy from BOOT if present)
if [[ -n "${BOOT_PART:-}" && -f "$BOOT_MOUNT/sysclone-first-boot.sh" ]]; then
  sudo install -Dm755 "$BOOT_MOUNT/sysclone-first-boot.sh" "$ROOT_MOUNT/usr/local/sbin/sysclone-first-boot.sh"
fi

# Enable the unit (symlink into multi-user.target.wants)
sudo mkdir -p "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf ../sysclone-first-boot.service \
  "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants/sysclone-first-boot.service"

sudo umount "$ROOT_MOUNT" || true
[[ -n "${BOOT_PART:-}" ]] && sudo umount "$BOOT_MOUNT" || true
echo "[install] done"
