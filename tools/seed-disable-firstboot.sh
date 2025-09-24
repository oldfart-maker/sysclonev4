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

mask_unit_name() {
  local name="$1"
  if [[ -f "$ROOT_MOUNT/usr/lib/systemd/system/$name" || -f "$ROOT_MOUNT/etc/systemd/system/$name" ]]; then
    echo "[seed] masking $name"
    sudo install -d "$ROOT_MOUNT/etc/systemd/system"
    sudo ln -snf /dev/null "$ROOT_MOUNT/etc/systemd/system/$name"
    # remove any wants/ symlink
    sudo find "$ROOT_MOUNT/etc/systemd/system" -type l -name "$name" -print -delete || true
    sudo find "$ROOT_MOUNT/usr/lib/systemd/system" -type l -name "$name" -print -delete || true
    sudo rm -f "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants/$name" || true
    sudo rm -f "$ROOT_MOUNT/etc/systemd/system/default.target.wants/$name" || true
  fi
}

# 1) Mask known names
for n in \
  manjaro-arm-firstboot.service \
  manjaro-firstboot.service \
  oem-firstboot.service \
  oem-setup-firstboot.service \
  systemd-firstboot-setup.service \
  firstboot.service
do
  mask_unit_name "$n"
done

# 1b) Mask any unit that *mentions* manjaro-arm-firstboot or firstboot in ExecStart
while IFS= read -r -d '' u; do
  if sudo grep -qiE 'manjaro-.*firstboot|firstboot' "$u"; then
    name="$(basename "$u")"
    mask_unit_name "$name"
  fi
done < <(sudo find "$ROOT_MOUNT/usr/lib/systemd/system" "$ROOT_MOUNT/etc/systemd/system" -maxdepth 1 -type f -name "*.service" -print0 2>/dev/null)

# 1c) Remove getty@tty1 overrides that launch the wizard
if [[ -d "$ROOT_MOUNT/etc/systemd/system/getty@tty1.service.d" ]]; then
  echo "[seed] removing getty@tty1 overrides (possible firstboot launcher)"
  sudo rm -rf "$ROOT_MOUNT/etc/systemd/system/getty@tty1.service.d"
fi

# 1d) Remove any stray wants/ symlinks to *firstboot*.service
sudo find "$ROOT_MOUNT/etc/systemd/system" -type l -name "*firstboot*.service" -print -delete || true

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

# 3) Ensure wheel sudoers active
if sudo test -f "$ROOT_MOUNT/etc/sudoers"; then
  sudo sed -i -E 's/^\s*#\s*(%wheel\s+ALL=\(ALL:ALL\)\s+ALL)/\1/' "$ROOT_MOUNT/etc/sudoers"
fi

# 4) Stamp
sudo install -d "$ROOT_MOUNT/var/lib/sysclone"
echo "1" | sudo tee "$ROOT_MOUNT/var/lib/sysclone/manjaro-firstboot-disabled" >/dev/null

# Done
sudo umount "$ROOT_MOUNT" || true
[[ -n "${BOOT_PART:-}" ]] && sudo umount "$BOOT_MOUNT" || true
echo "[seed] done"
