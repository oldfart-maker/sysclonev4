#!/usr/bin/env bash
set -euo pipefail
# sysclonev4: Unmount by mountpoints only (no DEVICE needed)
BOOT_MNT="${BOOT_MNT:-/mnt/sysclone-boot}"
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

unmount_if() {
  local mp="$1"
  if mountpoint -q "$mp" >/dev/null 2>&1; then
    sudo umount "$mp"
  fi
}

# Unmount root first, then boot
unmount_if "$ROOT_MNT"
unmount_if "$BOOT_MNT"
sync
echo "Unmounted (if mounted): $ROOT_MNT, $BOOT_MNT"
