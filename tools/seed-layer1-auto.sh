#!/usr/bin/env bash
set -euo pipefail

BOOT_MOUNT="/run/media/username/BOOT"
SRC="seeds/layer1/first-boot.sh"

# sanity
[[ -f "$SRC" ]] || { echo "[seed] ERROR: $SRC not found" >&2; exit 1; }

mkdir -p "$BOOT_MOUNT"

already_mounted=no
if mountpoint -q "$BOOT_MOUNT"; then
  already_mounted=yes
fi

mounted_dev=""
if [[ "$already_mounted" != "yes" ]]; then
  # scan all vfat block partitions and mount each candidate until we see Pi boot files
  while read -r dev fstype; do
    [[ "$fstype" == "vfat" ]] || continue
    if sudo mount -o uid="$(id -u)",gid="$(id -g)" "$dev" "$BOOT_MOUNT" 2>/dev/null; then
      if [[ -f "$BOOT_MOUNT/config.txt" || -f "$BOOT_MOUNT/cmdline.txt" || -f "$BOOT_MOUNT/start4.elf" ]]; then
        mounted_dev="$dev"
        break
      fi
      sudo umount "$BOOT_MOUNT" || true
    fi
  done < <(lsblk -pno NAME,FSTYPE)
fi

# verify we have a writable BOOT mount
if ! mountpoint -q "$BOOT_MOUNT"; then
  echo "[seed] ERROR: could not auto-mount BOOT (vfat). Mount it at $BOOT_MOUNT and re-run." >&2
  exit 1
fi

echo "[seed] Using BOOT at: $BOOT_MOUNT"
install -Dm644 "$SRC" "$BOOT_MOUNT/sysclone-first-boot.sh"
cat > "$BOOT_MOUNT/README-sysclone.txt" <<'R'
SysClone v4 Layer1 seed

On the Pi (after first boot):
  sudo install -Dm755 /boot/sysclone-first-boot.sh /usr/local/sbin/sysclone-first-boot.sh
  sudo /usr/local/sbin/sysclone-first-boot.sh
R

echo "[seed] Seed complete."
if [[ -n "$mounted_dev" ]]; then
  echo "[seed] Sync + unmount ($mounted_dev)"
  sync
  sudo umount "$BOOT_MOUNT"
fi
