#!/usr/bin/env bash
set -Eeuo pipefail

BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"
BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"
SUDO="${SUDO:-sudo}"

log(){ printf '[devices] %s\n' "$*"; }
err(){ printf '[devices] ERROR: %s\n' "$*" >&2; }
die(){ err "$*"; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }

dev_by_label() {
  local label="$1" p=""
  if have blkid; then
    p="$(blkid -L "$label" 2>/dev/null || true)"
    [[ -n "${p:-}" ]] && readlink -f -- "$p" && return 0
  fi
  if have lsblk; then
    p="$(lsblk -rpo NAME,LABEL | awk -v L="$label" '$2==L{print $1; exit}')"
    [[ -n "${p:-}" ]] && readlink -f -- "$p" && return 0
  fi
  return 1
}

mounted_at() {
  local dev="$1"
  findmnt -nr -S "$dev" -o TARGET 2>/dev/null || true
}

bind_if_elsewhere() {
  local dev="$1" want="$2"
  local cur; cur="$(mounted_at "$dev")"
  if [[ -n "$cur" && "$cur" != "$want" ]]; then
    log "$dev already mounted at $cur; bind-mounting to $want"
    $SUDO mkdir -p -- "$want"
    $SUDO mount --bind "$cur" "$want"
    return 0
  fi
  return 1
}

ensure_one_mounted() {
  local label="$1" dev mnt fstype
  dev="$(dev_by_label "$label")" || die "Could not find device with label $label"
  if [[ "$label" == "${BOOT_LABEL}" ]]; then
    mnt="$BOOT_MOUNT"; fstype="vfat"
  else
    mnt="$ROOT_MOUNT"; fstype="ext4"
  fi

  # If the device is mounted somewhere, bind it; otherwise do a fresh mount.
  if bind_if_elsewhere "$dev" "$mnt"; then
    echo "$mnt"; return 0
  fi

  # If the target path is mounted but not our device, unmount and continue.
  if findmnt -nr -T "$mnt" >/dev/null 2>&1; then
    local cur_dev; cur_dev="$(findmnt -nr -T "$mnt" -o SOURCE || true)"
    if [[ "$cur_dev" == "$dev" ]]; then
      log "already mounted: $mnt"
      echo "$mnt"; return 0
    fi
    log "remounting $mnt to correct device ($dev)"
    $SUDO umount -R "$mnt" || $SUDO umount -Rl "$mnt" || true
  fi

  $SUDO mkdir -p -- "$mnt"
  log "mounting $label ($dev) -> $mnt"
  if ! $SUDO mount "$dev" "$mnt" 2>/dev/null; then
    $SUDO mount -t "$fstype" "$dev" "$mnt"
  fi
  echo "$mnt"
}

lazy_unmount_path() {
  local path="$1"
  if findmnt -nr -T "$path" >/dev/null 2>&1; then
    log "unmounting $path"
    $SUDO umount -R "$path" || $SUDO umount -Rl "$path" || true
  fi
}

ensure-mounted() {
  log "ensure-mounted: $ROOT_LABEL -> $ROOT_MOUNT and $BOOT_LABEL -> $BOOT_MOUNT"
  ensure_one_mounted "$ROOT_LABEL" >/dev/null
  ensure_one_mounted "$BOOT_LABEL"  >/dev/null
  log "mounts:"
  findmnt -nr -o SOURCE,TARGET | grep -E 'sysclone-(boot|root)|BOOT|ROOT' || true
}

ensure-unmounted() {
  log "ensure-unmounted: $BOOT_MOUNT and $ROOT_MOUNT"
  lazy_unmount_path "$BOOT_MOUNT"
  lazy_unmount_path "$ROOT_MOUNT"
  local dev
  for L in "$BOOT_LABEL" "$ROOT_LABEL"; do
    if dev="$(dev_by_label "$L")"; then
      local t; t="$(mounted_at "$dev")"
      if [[ -n "${t:-}" ]]; then
        log "unmounting $dev from $t"
        $SUDO umount -R "$t" || $SUDO umount -Rl "$t" || true
      fi
    fi
  done
}

resolve-disk() {
  local dev parent
  for L in "$BOOT_LABEL" "$ROOT_LABEL"; do
    if dev="$(dev_by_label "$L")"; then
      parent="$(lsblk -nrpo PKNAME "$dev" 2>/dev/null | head -n1)"
      parent="${parent:-$(lsblk -nrpo NAME "$dev" | sed -E 's/[0-9]+$//;s/p[0-9]+$//')}"
      echo "$L -> $dev (disk: ${parent:-unknown})"
    else
      echo "$L -> (not found)"
    fi
  done
}

if [[ "${BASH_SOURCE[0]-}" == "$0" ]]; then
  case "${1:-}" in
    ensure-mounted)   ensure-mounted ;;
    ensure-unmounted) ensure-unmounted ;;
    resolve-disk)     resolve-disk ;;
    *) echo "usage: tools/devices.sh {ensure-mounted|ensure-unmounted|resolve-disk}" >&2; exit 2 ;;
  esac
fi
