#!/usr/bin/env bash
# Manual expand: accept either a DISK (/dev/sdX|/dev/mmcblk0|/dev/nvme0n1)
# or the ROOT PARTITION (/dev/sdX2|/dev/mmcblk0p2|/dev/nvme0n1p2).
set -Eeuo pipefail
: "${DEVICE:?Set DEVICE to disk (/dev/sdX) or root partition (/dev/sdX2)}"

die(){ echo "[expand] ERROR: $*" >&2; exit 1; }

# Normalize to real path if exists
if [[ -e "$DEVICE" ]]; then
  DEVICE="$(readlink -f -- "$DEVICE")"
fi

# Detect if DEVICE is a partition (ends with a digit, nvme/mmc use pN)
is_part=0
if [[ "$DEVICE" =~ p?[0-9]+$ ]]; then
  is_part=1
fi

disk=""
rootpart=""

if (( is_part )); then
  # DEVICE is a partition; verify it exists as block
  [[ -b "$DEVICE" ]] || die "not a block device (partition): $DEVICE"
  rootpart="$DEVICE"

  # Use lsblk to find parent disk name (e.g., 'sdc'); fall back to /sys if needed
  pk="$(lsblk -nrpo PKNAME "$rootpart" 2>/dev/null | head -n1 || true)"
  if [[ -z "$pk" ]]; then
    # Try via /sys: /sys/dev/block/MAJ:MIN -> .../block/<disk>/<part>
    majmin="$(stat -c '%t:%T' "$rootpart" 2>/dev/null || true)"
    [[ -n "$majmin" ]] || die "cannot resolve parent for $rootpart"
    syslink="$(readlink -f "/sys/dev/block/$(stat -c '%t:%T' "$rootpart")" 2>/dev/null || true)"
    [[ -n "$syslink" ]] || die "cannot resolve /sys for $rootpart"
    pk="$(basename "$(dirname "$syslink")")"
  else
    pk="$(basename "$pk")"
  fi
  [[ -n "$pk" ]] || die "cannot derive parent disk for $rootpart"
  disk="/dev/$pk"
else
  # DEVICE is a disk
  disk="$DEVICE"
  # derive root partition path (partition 2)
  case "$disk" in
    *mmcblk*|*nvme*) rootpart="${disk}p2" ;;
    *)               rootpart="${disk}2" ;;
  esac
fi

# Ensure disk node exists; if missing, re-create from /sys (major:minor)
if [[ ! -b "$disk" ]]; then
  dname="$(basename "$disk")"
  sysdev="/sys/class/block/$dname/dev"
  [[ -r "$sysdev" ]] || die "disk node $disk missing and $sysdev not readable"
  majmin="$(cat "$sysdev")" || die "cannot read $sysdev"
  maj="${majmin%:*}"; min="${majmin#*:}"
  echo "[expand] creating missing block node $disk (b $maj $min)"
  sudo mknod "$disk" b "$maj" "$min"
  sudo chmod 660 "$disk"
fi

# Settle & reread partition table
command -v partprobe >/dev/null && sudo partprobe "$disk" || true
sync; command -v udevadm >/dev/null && sudo udevadm settle || true

echo "[expand] grow partition 2 on $disk to 100%"
sudo parted -s "$disk" unit % print >/dev/null
sudo parted -s "$disk" -- resizepart 2 100%

# Settle again before touching FS
command -v partprobe >/dev/null && sudo partprobe "$disk" || true
sync; command -v udevadm >/dev/null && sudo udevadm settle || true

# Ensure root partition node exists (it should)
[[ -b "$rootpart" ]] || die "root partition node missing: $rootpart"

echo "[expand] fsck+resize2fs on $rootpart"
sudo e2fsck -fp "$rootpart" || true
sudo resize2fs "$rootpart"

echo "[expand] done"
