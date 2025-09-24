#!/usr/bin/env bash
set -Eeuo pipefail

# Inputs
DEVICE="${DEVICE:-}"                       # e.g. /dev/sdd or /dev/mmcblk0
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
# BOOT not strictly needed, but mount if present
[[ -n "${BOOT_PART:-}" ]] && sudo mount "$BOOT_PART" "$BOOT_MOUNT" 2>/dev/null || true
sudo mount "$ROOT_PART" "$ROOT_MOUNT"

echo "[seed] ROOT=$ROOT_PART mounted at $ROOT_MOUNT"
[[ -n "${BOOT_PART:-}" ]] && echo "[seed] BOOT=$BOOT_PART mounted at $BOOT_MOUNT"

# 1) Mask likely first-boot units (only if they exist)
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

# 2) Preseed basic system settings
echo "[seed] preseed hostname/locale/keymap/timezone"
sudo tee "$ROOT_MOUNT/etc/hostname" >/dev/null <<< "archpi5"

# enable en_US.UTF-8 in locale.gen
if sudo test -f "$ROOT_MOUNT/etc/locale.gen"; then
  sudo sed -i -E 's/^#\s*en_US\.UTF-8\s+UTF-8/en_US.UTF-8 UTF-8/' "$ROOT_MOUNT/etc/locale.gen"
else
  echo "en_US.UTF-8 UTF-8" | sudo tee -a "$ROOT_MOUNT/etc/locale.gen" >/dev/null
fi
echo "LANG=en_US.UTF-8" | sudo tee "$ROOT_MOUNT/etc/locale.conf" >/dev/null

# console keymap
echo "KEYMAP=us" | sudo tee "$ROOT_MOUNT/etc/vconsole.conf" >/dev/null

# timezone + localtime
echo "America/New_York" | sudo tee "$ROOT_MOUNT/etc/timezone" >/dev/null
sudo ln -snf "../usr/share/zoneinfo/America/New_York" "$ROOT_MOUNT/etc/localtime"

# Optional: create the 'username' user on the rootfs (only if not present).
# This avoids Manjaro's wizard asking for a user. We'll still let your oneshot adjust sudoers.
if ! sudo chroot "$ROOT_MOUNT" id -u username >/dev/null 2>&1; then
  echo "[seed] creating user 'username' with wheel"
  sudo chroot "$ROOT_MOUNT" useradd -m -G wheel -s /bin/bash username
  echo "username:username" | sudo chroot "$ROOT_MOUNT" chpasswd
fi

# Ensure wheel sudoers line is active
if sudo test -f "$ROOT_MOUNT/etc/sudoers"; then
  sudo sed -i -E 's/^\s*#\s*(%wheel\s+ALL=\(ALL:ALL\)\s+ALL)/\1/' "$ROOT_MOUNT/etc/sudoers"
fi

# 3) Stamp that we disabled Manjaro first-boot (for your own sanity)
sudo install -d "$ROOT_MOUNT/var/lib/sysclone"
sudo tee "$ROOT_MOUNT/var/lib/sysclone/manjaro-firstboot-disabled" >/dev/null <<< "1"

# Unmount
sudo umount "$ROOT_MOUNT" || true
[[ -n "${BOOT_PART:-}" ]] && sudo umount "$BOOT_MOUNT" || true
echo "[seed] done"
