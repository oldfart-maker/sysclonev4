#!/usr/bin/env bash
set -Eeuo pipefail
file=Makefile

block='
# --- sysclone host-side rootfs expansion (offline) --------------------------
DEVICE ?= /dev/mmcblk0
ROOT_MNT ?= /mnt/sysclone-root
BOOT_MNT ?= /mnt/sysclone-boot

.PHONY: img-expand-rootfs-offline verify-rootfs-size sd-write+expand

## Expand rootfs offline on the SD card (requires DEVICE=/dev/...)
img-expand-rootfs-offline: ensure-unmounted
	@echo "[make] offline expand on $(DEVICE)"
	DEVICE=$(DEVICE) ROOT_MNT=$(ROOT_MNT) BOOT_MNT=$(BOOT_MNT) sudo tools/host-expand-rootfs.sh

## Convenience: write image then expand offline
sd-write+expand: sd-write img-expand-rootfs-offline

## Quick check (mounted): shows sizes for sanity
verify-rootfs-size: ensure-mounted
	@echo "[make] verify sizes on mounted card"
	@lsblk -e7 -o NAME,SIZE,TYPE,MOUNTPOINTS | sed -n "1,200p"
	@df -h | sed -n "1,200p"
	@echo "[make] .rootfs-expanded stamp:" && ls -l $(ROOT_MNT)/var/lib/sysclone/.rootfs-expanded || true
# ---------------------------------------------------------------------------
'

grep -q '^img-expand-rootfs-offline:' "$file" || {
  printf '%s\n' "$block" >> "$file"
  echo "[update] appended host expand targets to $file"
}
