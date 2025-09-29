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
log "resizing partition 2 to 100% on $DEVICE"
# capture current p2 size to detect change later
old_sz="$(blockdev --getsz "${DEVICE}2" 2>/dev/null || echo 0)"

if command -v sfdisk >/dev/null 2>&1; then
  log "using sfdisk dump+rewrite to grow p2 with explicit size; keep type 83; avoid reread hang"
  dump="$(sfdisk -d "$DEVICE" 2>/dev/null || true)"
  p2start="$(printf '%s\n' "$dump" | awk -v dev="$DEVICE" '
    BEGIN{s=""}
    $1==dev "2" && $2==":" {
      for (i=1;i<=NF;i++) if ($i ~ /^start=/) { gsub(/start=|,/, "", $i); s=$i; break }
      if (s!="") { print s; exit }
    }')"
  # Fallback: parted (machine-readable), unit sectors
  if [ -z "$p2start" ]; then
    p2start="$(parted -sm "$DEVICE" unit s print 2>/dev/null       | awk -F: '$1=="2"{ gsub(/s$/,"",$2); print $2; exit }')"
  fi
  [ -n "$p2start" ] || die "failed to parse start for ${DEVICE}2"

  # compute total sectors and target size (end to last sector)
  total="$(blockdev --getsz "$DEVICE" || true)"
  [ -n "$total" ] || die "failed to read total sectors for $DEVICE"
  newsize="$(( total - p2start ))"
  [ "$newsize" -gt 0 ] || die "computed non-positive size for ${DEVICE}2 (total=$total start=$p2start)"

  # rewrite p2 explicitly with same start, explicit size, and Linux type (0x83)
  echo ",+" | sfdisk -N 2 --no-reread --force "$DEVICE"

elif command -v parted >/dev/null 2>&1; then
  log "using parted to expand partition 2 (fallback)"
  parted -s "$DEVICE" ---pretend-input-tty <<CMD || true
unit %
print
resizepart 2 100%
Yes
print
CMD
else
  die "no sfdisk/parted available"
fi

# refresh kernel view of the new table

# refresh kernel view of the new table
log "refreshing kernel partition table (partprobe/partx) and udev"
partprobe "$DEVICE" || true
partx -u "$DEVICE" || true
udevadm settle || true
sleep 1

# verify boot partition still present
[ -b "${DEVICE}1" ] || die "boot (p1) disappeared after grow; refusing to continue"
partprobe "$DEVICE" || true
partx -u "$DEVICE" || true
udevadm settle || true
sleep 1

# verify growth; fail loudly if unchanged
new_sz="$(blockdev --getsz "${DEVICE}2" 2>/dev/null || echo 0)"
log "p2 sectors: old=$old_sz new=$new_sz (device total=$(blockdev --getsz "$DEVICE" || echo ?))"
[ "$new_sz" -gt "$old_sz" ] || die "p2 did not grow (old=$old_sz new=$new_sz)"

# re-read table
log "running partprobe"
partprobe "$DEVICE" || true
partx -u "$DEVICE" || true
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
