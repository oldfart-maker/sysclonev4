#!/usr/bin/env bash
set -Eeuo pipefail
DISK="${1:-}"
[[ -n "$DISK" ]] || { echo "[expand] usage: $0 /dev/sdX|/dev/mmcblk0|/dev/nvme0n1" >&2; exit 2; }
[[ -b "$DISK" ]] || { echo "[expand] ERROR: not a block device: $DISK" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
sfx=""; [[ "$DISK" =~ (mmcblk|nvme) ]] && sfx="p"
ROOT_PART="${DISK}${sfx}2"
lsblk -no NAME "$ROOT_PART" >/dev/null 2>&1 || { echo "[expand] ERROR: expected root partition #2: $ROOT_PART" >&2; exit 1; }
have partprobe && partprobe "$DISK" || true; sync; have udevadm && udevadm settle || true
echo "[expand] resizing partition 2 to 100% on $DISK"
parted -s "$DISK" unit % print >/dev/null
parted -s "$DISK" -- resizepart 2 100%
have partprobe && partprobe "$DISK" || true; sync; have udevadm && udevadm settle || true
echo "[expand] fsck + resize2fs on $ROOT_PART"
e2fsck -fp "$ROOT_PART" || true
resize2fs "$ROOT_PART"
echo "[expand] done"
