#!/usr/bin/env bash
set -Eeuo pipefail
: "${DEVICE:?Set DEVICE=/dev/sdX (or /dev/mmcblk0, /dev/nvme0n1)}"

if [[ ! -b "$DEVICE" ]]; then
  echo "[expand] ERROR: not a block device: $DEVICE" >&2
  exit 1
fi

# suffix for partition 2 (mmc/nvme use 'p')
sfx=""; case "$DEVICE" in *mmcblk*|*nvme*) sfx="p";; esac
ROOT_PART="${DEVICE}${sfx}2"

# settle & (re)read partition table
command -v partprobe >/dev/null && partprobe "$DEVICE" || true
sync
command -v udevadm  >/dev/null && udevadm settle || true

echo "[expand] grow partition 2 on $DEVICE to 100%"
parted -s "$DEVICE" unit % print >/dev/null
parted -s "$DEVICE" -- resizepart 2 100%

# settle again before touching FS
command -v partprobe >/dev/null && partprobe "$DEVICE" || true
sync
command -v udevadm  >/dev/null && udevadm settle || true

echo "[expand] fsck+resize2fs on $ROOT_PART"
e2fsck -fp "$ROOT_PART" || true
resize2fs "$ROOT_PART"
echo "[expand] done"
