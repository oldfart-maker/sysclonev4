#!/usr/bin/env bash
set -Eeuo pipefail
: "${DEVICE:?set DEVICE=/dev/sdX (or /dev/mmcblk0, /dev/nvme0n1)}"

ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"
BOOT_MNT="${BOOT_MNT:-/mnt/sysclone-boot}"

log(){ printf '[host-expand] %s\n' "$*"; }
die(){ printf '[host-expand] ERROR: %s\n' "$*" >&2; exit 1; }

# partition suffix for mmc/nvme vs sdX
suffix=""
[[ "$DEVICE" =~ (mmcblk|nvme) ]] && suffix="p"
PART="${DEVICE}${suffix}2"

# safety checks
[ -b "$DEVICE" ] || die "not a block device: $DEVICE"
[ -b "$PART"   ] || die "root partition not found: $PART"

# ensure not mounted
mountpoint -q "$ROOT_MNT" && die "root is mounted at $ROOT_MNT (unmount first)"
mountpoint -q "$BOOT_MNT" && die "boot is mounted at $BOOT_MNT (unmount first)"
grep -qs "$PART " /proc/mounts && die "$PART appears mounted; unmount before proceeding"

log "pre lsblk:"
lsblk -e7 -o NAME,SIZE,TYPE,MOUNTPOINTS "$DEVICE" || true

log "pre parted print:"
parted -s "$DEVICE" unit s print || true

# grow partition 2 to 100%
log "resizing partition 2 to 100%% on $DEVICE"
parted -s "$DEVICE" ---pretend-input-tty <<CMD
unit %
print
resizepart 2 100%
Yes
print
CMD

# re-read table
log "running partprobe"
partprobe "$DEVICE" || true
udevadm settle || true
sleep 1

log "post parted print:"
parted -s "$DEVICE" unit s print || true

# fsck + resize2fs on the root partition
log "running e2fsck -f on $PART"
e2fsck -pf "$PART" || true

log "running resize2fs on $PART"
resize2fs "$PART"

log "post lsblk:"
lsblk -e7 -o NAME,SIZE,TYPE,MOUNTPOINTS "$DEVICE" || true

# optional: stamp so on-target service no-ops
log "stamping .rootfs-expanded on the target root"
mkdir -p "$ROOT_MNT" && mount "$PART" "$ROOT_MNT"
install -d -m 0755 "$ROOT_MNT/var/lib/sysclone"
touch "$ROOT_MNT/var/lib/sysclone/.rootfs-expanded"
umount "$ROOT_MNT" || true

log "done"
