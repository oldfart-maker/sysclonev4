#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"
echo "[layer1] seed-expand-rootfs: stub (no-op)."
echo "         OK to ignore; card will boot with current 3.4G rootfs."
echo "         We can replace this with a proper first-boot expander later."
exit 0
