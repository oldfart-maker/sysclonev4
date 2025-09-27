#!/usr/bin/env bash
set -euo pipefail
# sysclonev4: Idempotent mount helper (no bind-mounts)
# If DEVICE is set (/dev/sdX, /dev/mmcblk0, /dev/nvme0n1), use it.
# Else, autodetect exactly one Pi-style SD card:
#  - vfat boot with config.txt
#  - ext4 root with /etc/os-release mentioning Arch

BOOT_MNT="${BOOT_MNT:-/mnt/sysclone-boot}"
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

autodetect_device() {
  local cands=()
  for disk in /sys/block/{sd?,sd??,mmcblk?,nvme?n1}; do
    [ -e "$disk" ] || continue
    local d="/dev/$(basename "$disk")"
    local p1 p2
    if ls "${d}"p1 >/dev/null 2>&1; then
      p1="${d}p1"; p2="${d}p2"
    else
      p1="${d}1"; p2="${d}2"
    fi
    [ -b "$p1" ] && [ -b "$p2" ] || continue

    local t1 t2
    t1="$(blkid -o value -s TYPE "$p1" 2>/dev/null || true)"
    t2="$(blkid -o value -s TYPE "$p2" 2>/dev/null || true)"

    local bootpart="" rootpart=""
    if [ "$t1" = "vfat" ]; then bootpart="$p1"; rootpart="$p2"
    elif [ "$t2" = "vfat" ]; then bootpart="$p2"; rootpart="$p1"
    else continue; fi

    local tmpb tmpr; tmpb="$(mktemp -d)"; tmpr="$(mktemp -d)"
    if sudo mount -t vfat "$bootpart" "$tmpb" 2>/dev/null; then
      if [ -f "$tmpb/config.txt" ] || [ -f "$tmpb/boot/config.txt" ]; then
        if sudo mount "$rootpart" "$tmpr" 2>/dev/null; then
          if [ -f "$tmpr/etc/os-release" ] && grep -qi 'arch' "$tmpr/etc/os-release"; then
            cands+=("$d:$bootpart:$rootpart")
          fi
          sudo umount "$tmpr" || true
        fi
      fi
      sudo umount "$tmpb" || true
    fi
    rmdir "$tmpb" "$tmpr" 2>/dev/null || true
  done

  if [ "${#cands[@]}" -eq 1 ]; then printf '%s\n' "${cands[0]}"; return 0; fi
  if [ "${#cands[@]}" -eq 0 ]; then
    echo "ERROR: Autodetect found no suitable SD card. Set DEVICE=/dev/..." >&2
  else
    echo "ERROR: Multiple candidates found:" >&2
    for c in "${cands[@]}"; do echo "  $c" >&2; done
    echo "Refusing to guess. Set DEVICE=/dev/..." >&2
  fi
  return 1
}

DEVICE="${DEVICE:-}"
P1=""; P2=""
if [ -z "$DEVICE" ]; then
  read -r DEVICE P1 P2 < <(autodetect_device | awk -F: '{print $1, $2, $3}')
else
  case "$DEVICE" in
    *mmcblk*|*nvme*|*loop*) P1="${DEVICE}p1"; P2="${DEVICE}p2" ;;
    *)                      P1="${DEVICE}1";  P2="${DEVICE}2"  ;;
  esac
fi

# safety: refuse if DEVICE seems tied to /
if findmnt -rn -o SOURCE,TARGET | awk -v dev="$DEVICE" '{ if (index($1,dev)==1 && $2=="/"){f=1} } END{exit f?0:1}'; then
  echo "ERROR: $DEVICE appears to host /; refusing." >&2
  exit 3
fi

[ -b "$P1" ] || { echo "ERROR: boot part not found: $P1" >&2; exit 4; }
[ -b "$P2" ] || { echo "ERROR: root part not found: $P2" >&2; exit 5; }

sudo mkdir -p "$BOOT_MNT" "$ROOT_MNT"

check_mount_matches() {
  local mp="$1" dev="$2"
  if mountpoint -q "$mp" >/dev/null 2>&1; then
    local src; src="$(findmnt -rn -o SOURCE --target "$mp")"
    [ "$src" = "$dev" ] || { echo "ERROR: $mp already mounted from $src (expected $dev)"; exit 6; }
    return 0
  fi
  return 1
}

# Mount boot (no bind-mounts)
if ! check_mount_matches "$BOOT_MNT" "$P1"; then
  if ! sudo sudo mount -t vfat "$P1" "$BOOT_MNT" 2>/dev/null; then
    sudo mount "$P1" "$BOOT_MNT"
  fi
fi

# Mount root
if ! check_mount_matches "$ROOT_MNT" "$P2"; then
  sudo mount "$P2" "$ROOT_MNT"
fi

mkdir -p .cache/sysclonev4
printf "%s\n" "$DEVICE" > .cache/sysclonev4/last-device

echo "Mounted:"
{
  findmnt -rno TARGET,SOURCE "$BOOT_MNT" "$ROOT_MNT"
} || true
exit 0

# --- override: correct mount check using mountpoint + findmnt --target ---
check_mount_matches() {
  local mp="$1" dev="$2"
  if mountpoint -q "$mp"; then
    local src
    src="$(findmnt -rn -o SOURCE --target "$mp")"
    if [ "$src" != "$dev" ]; then
      echo "ERROR: $mp already mounted from $src (expected $dev)"
      exit 6
    fi
    return 0
  fi
  return 1
}
