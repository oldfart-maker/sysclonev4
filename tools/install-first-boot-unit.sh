#!/usr/bin/env bash
set -Eeuo pipefail
BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"

# figure out partitions
if [[ -n "${DEVICE:-}" ]]; then
  BOOT_PART="${DEVICE}1"; ROOT_PART="${DEVICE}2"
  [[ "$DEVICE" =~ mmcblk ]] && BOOT_PART="${DEVICE}p1" && ROOT_PART="${DEVICE}p2"
else
  # fallback: by label
  BOOT_PART="$(lsblk -pno NAME,LABEL,FSTYPE | awk '$2=="BOOT_MNJRO"||$2=="BOOT"{print $1; exit}')"
  ROOT_PART="$(lsblk -pno NAME,LABEL,FSTYPE | awk '$2=="ROOT_MNJRO"||$2=="rootfs"{print $1; exit}')"
fi

[[ -n "$BOOT_PART" && -n "$ROOT_PART" ]] || { echo "[install] ERROR: could not detect BOOT/ROOT partitions"; exit 1; }

sudo mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"
sudo mount "$BOOT_PART" "$BOOT_MOUNT"
sudo mount "$ROOT_PART" "$ROOT_MOUNT"

echo "[install] BOOT=$BOOT_PART mounted at $BOOT_MOUNT"
echo "[install] ROOT=$ROOT_PART mounted at $ROOT_MOUNT"

# copy provisioning script + unit into ROOT
sudo install -Dm755 seeds/layer1/first-boot-provision.sh "$ROOT_MOUNT/usr/local/lib/sysclone/first-boot-provision.sh"
sudo install -Dm644 seeds/layer1/first-boot.service "$ROOT_MOUNT/etc/systemd/system/sysclone-first-boot.service"

# ensure the sysclone-first-boot.sh exists on ROOT; if only on BOOT, copy it over
if [[ -f "$BOOT_MOUNT/sysclone-first-boot.sh" ]]; then
  sudo install -Dm755 "$BOOT_MOUNT/sysclone-first-boot.sh" "$ROOT_MOUNT/usr/local/sbin/sysclone-first-boot.sh"
fi

# enable the unit by creating Wants/ symlink (no chroot needed)
sudo mkdir -p "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf ../sysclone-first-boot.service \
  "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants/sysclone-first-boot.service"

echo "[install] Enabled: sysclone-first-boot.service (via Wants/ symlink)"

# unmount
sudo umount "$BOOT_MOUNT" || true
sudo umount "$ROOT_MOUNT" || true
echo "[install] done"
