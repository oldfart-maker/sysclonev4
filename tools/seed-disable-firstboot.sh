#!/usr/bin/env bash
set -Eeuo pipefail

log(){ [[ "${QUIET:-0}" = "1" ]] || echo "$@"; }

BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"

# ----- pick partitions: prefer explicit ROOT_PART/BOOT_PART; then DEVICE; then labels -----
if [[ -n "${ROOT_PART:-}" ]]; then
  : # use ROOT_PART/BOOT_PART as provided
elif [[ -n "${DEVICE:-}" ]]; then
  if [[ "$DEVICE" =~ mmcblk|nvme ]]; then BOOT_PART="${DEVICE}p1"; ROOT_PART="${DEVICE}p2"; else BOOT_PART="${DEVICE}1"; ROOT_PART="${DEVICE}2"; fi
else
  BOOT_PART="$(lsblk -pno NAME,LABEL | awk '$2=="BOOT_MNJRO"||$2=="BOOT"{print $1; exit}')"
  ROOT_PART="$(lsblk -pno NAME,LABEL | awk '$2=="ROOT_MNJRO"||$2=="rootfs"{print $1; exit}')"
fi
[[ -n "${ROOT_PART:-}" ]] || { echo "[seed] ERROR: cannot determine ROOT_PART"; exit 1; }

sudo mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"
[[ -n "${BOOT_PART:-}" ]] && sudo mount "$BOOT_PART" "$BOOT_MOUNT" 2>/dev/null || true
sudo mount "$ROOT_PART" "$ROOT_MOUNT"

log "[seed] ROOT=$ROOT_PART mounted at $ROOT_MOUNT"
[[ -n "${BOOT_PART:-}" ]] && log "[seed] BOOT=$BOOT_PART mounted at $BOOT_MOUNT"

mask_unit() {
  local name="$1"
  if [[ -f "$ROOT_MOUNT/usr/lib/systemd/system/$name" || -f "$ROOT_MOUNT/etc/systemd/system/$name" ]]; then
    # idempotent: only say something if not already masked to /dev/null
    local link="$ROOT_MOUNT/etc/systemd/system/$name"
    if [[ ! -L "$link" || "$(readlink -f "$link")" != "/dev/null" ]]; then
      log "[seed] masking $name"
      sudo install -d "$ROOT_MOUNT/etc/systemd/system"
      sudo ln -snf /dev/null "$link"
    fi
    sudo rm -f "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants/$name" || true
    sudo rm -f "$ROOT_MOUNT/etc/systemd/system/default.target.wants/$name" || true
  fi
}

# 1) Mask known first-boot units (and homed’s firstboot, harmless but noisy)
for n in manjaro-arm-firstboot.service manjaro-firstboot.service oem-firstboot.service oem-setup-firstboot.service systemd-firstboot-setup.service firstboot.service systemd-homed-firstboot.service; do
  mask_unit "$n"
done

# Also mask any *.service referencing firstboot/oem/setup in ExecStart
while IFS= read -r -d '' u; do
  if sudo grep -qiE '(manjaro-.*firstboot|firstboot|oem-setup|oem.*firstboot)' "$u"; then
    mask_unit "$(basename "$u")"
  fi
done < <(sudo find "$ROOT_MOUNT/usr/lib/systemd/system" "$ROOT_MOUNT/etc/systemd/system" -maxdepth 1 -type f -name '*.service' -print0 2>/dev/null)

# 2) Remove getty@tty1 launch points
sudo rm -rf "$ROOT_MOUNT/etc/systemd/system/getty@tty1.service.d" 2>/dev/null || true
[[ -L "$ROOT_MOUNT/etc/systemd/system/getty@tty1.service" ]] && sudo rm -f "$ROOT_MOUNT/etc/systemd/system/getty@tty1.service"

# 3) Remove login-shell hooks & stub common binaries
sudo find "$ROOT_MOUNT/etc/profile.d" -maxdepth 1 -type f -iregex '.*first.*boot.*' -delete 2>/dev/null || true
stub() {
  local p="$1"
  if [[ -f "$ROOT_MOUNT/$p" ]]; then
    log "[seed] stubbing $p"
    sudo tee "$ROOT_MOUNT/$p" >/dev/null <<'E'
#!/usr/bin/env sh
# stubbed by sysclone: do nothing
exit 0
E
    sudo chmod +x "$ROOT_MOUNT/$p"
  fi
}
stub usr/bin/manjaro-arm-firstboot
stub usr/bin/oem-firstboot
stub usr/bin/oem-setup

# 4) Preseed basics (files only; no chroot)
echo "archpi5" | sudo tee "$ROOT_MOUNT/etc/hostname" >/dev/null
if sudo test -f "$ROOT_MOUNT/etc/locale.gen"; then
  sudo sed -i -E 's/^#\s*en_US\.UTF-8\s+UTF-8/en_US.UTF-8 UTF-8/' "$ROOT_MOUNT/etc/locale.gen"
else
  echo "en_US.UTF-8 UTF-8" | sudo tee -a "$ROOT_MOUNT/etc/locale.gen" >/dev/null
fi
echo "LANG=en_US.UTF-8" | sudo tee "$ROOT_MOUNT/etc/locale.conf" >/dev/null
echo "KEYMAP=us"        | sudo tee "$ROOT_MOUNT/etc/vconsole.conf" >/dev/null
echo "America/New_York" | sudo tee "$ROOT_MOUNT/etc/timezone" >/dev/null
sudo ln -snf "../usr/share/zoneinfo/America/New_York" "$ROOT_MOUNT/etc/localtime"

# Ensure wheel sudoers
if sudo test -f "$ROOT_MOUNT/etc/sudoers"; then
  sudo sed -i -E 's/^\s*#\s*(%wheel\s+ALL=\(ALL:ALL\)\s+ALL)/\1/' "$ROOT_MOUNT/etc/sudoers"
fi

# Stamp
sudo install -d "$ROOT_MOUNT/var/lib/sysclone"
echo "1" | sudo tee "$ROOT_MOUNT/var/lib/sysclone/manjaro-firstboot-disabled" >/dev/null

sudo umount "$ROOT_MOUNT" || true
[[ -n "${BOOT_PART:-}" ]] && sudo umount "$BOOT_MOUNT" || true
log "[seed] done"
