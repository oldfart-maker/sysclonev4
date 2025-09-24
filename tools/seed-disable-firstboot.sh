#!/usr/bin/env bash
set -Eeuo pipefail

DEVICE="${DEVICE:-}"                       # e.g. /dev/sdc or /dev/mmcblk0
BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"

# Resolve partitions
if [[ -n "$DEVICE" ]]; then
  BOOT_PART="${DEVICE}1"; ROOT_PART="${DEVICE}2"
  [[ "$DEVICE" =~ mmcblk ]] && BOOT_PART="${DEVICE}p1" && ROOT_PART="${DEVICE}p2"
else
  BOOT_PART="$(lsblk -pno NAME,LABEL | awk '$2=="BOOT_MNJRO"||$2=="BOOT"{print $1; exit}')"
  ROOT_PART="$(lsblk -pno NAME,LABEL | awk '$2=="ROOT_MNJRO"||$2=="rootfs"{print $1; exit}')"
fi
[[ -n "${ROOT_PART:-}" ]] || { echo "[seed] ERROR: cannot find ROOT partition"; exit 1; }

sudo mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"
[[ -n "${BOOT_PART:-}" ]] && sudo mount "$BOOT_PART" "$BOOT_MOUNT" 2>/dev/null || true
sudo mount "$ROOT_PART" "$ROOT_MOUNT"

echo "[seed] ROOT=$ROOT_PART mounted at $ROOT_MOUNT"
[[ -n "${BOOT_PART:-}" ]] && echo "[seed] BOOT=$BOOT_PART mounted at $BOOT_MOUNT"

# 1) Mask Manjaro/OEM first-boot units if present
mask_unit() {
  local name="$1"
  if [[ -f "$ROOT_MOUNT/usr/lib/systemd/system/$name" || -f "$ROOT_MOUNT/etc/systemd/system/$name" ]]; then
    echo "[seed] masking $name"
    sudo install -d "$ROOT_MOUNT/etc/systemd/system"
    sudo ln -snf /dev/null "$ROOT_MOUNT/etc/systemd/system/$name"
  fi
}
mask_unit manjaro-arm-firstboot.service
mask_unit oem-firstboot.service
mask_unit oem-setup-firstboot.service
mask_unit systemd-firstboot-setup.service

# 2) Preseed hostname/locale/keymap/timezone (file edits only, no chroot)
echo "[seed] preseed hostname/locale/keymap/timezone"
echo "archpi5" | sudo tee "$ROOT_MOUNT/etc/hostname" >/dev/null

# locale
if sudo test -f "$ROOT_MOUNT/etc/locale.gen"; then
  sudo sed -i -E 's/^#\s*en_US\.UTF-8\s+UTF-8/en_US.UTF-8 UTF-8/' "$ROOT_MOUNT/etc/locale.gen"
else
  echo "en_US.UTF-8 UTF-8" | sudo tee -a "$ROOT_MOUNT/etc/locale.gen" >/dev/null
fi
echo "LANG=en_US.UTF-8" | sudo tee "$ROOT_MOUNT/etc/locale.conf" >/dev/null

# keymap
echo "KEYMAP=us" | sudo tee "$ROOT_MOUNT/etc/vconsole.conf" >/dev/null

# timezone
echo "America/New_York" | sudo tee "$ROOT_MOUNT/etc/timezone" >/dev/null
sudo ln -snf "../usr/share/zoneinfo/America/New_York" "$ROOT_MOUNT/etc/localtime"

# 3) Ensure wheel sudoers is active (so our oneshot-created user can sudo)
if sudo test -f "$ROOT_MOUNT/etc/sudoers"; then
  sudo sed -i -E 's/^\s*#\s*(%wheel\s+ALL=\(ALL:ALL\)\s+ALL)/\1/' "$ROOT_MOUNT/etc/sudoers"
fi

# 4) Stamp for sanity
sudo install -d "$ROOT_MOUNT/var/lib/sysclone"
echo "1" | sudo tee "$ROOT_MOUNT/var/lib/sysclone/manjaro-firstboot-disabled" >/dev/null

# Done
sudo umount "$ROOT_MOUNT" || true
[[ -n "${BOOT_PART:-}" ]] && sudo umount "$BOOT_MOUNT" || true
echo "[seed] done"
