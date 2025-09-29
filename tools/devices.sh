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

# --- exact helpers ---
is_path_mounted() {
  # True only if THIS exact path is a mountpoint (not a parent)
  local want="$1" t
  t="$(findmnt -nr -T "$want" -o TARGET 2>/dev/null || true)"
  [[ "$t" == "$want" ]]
}

src_dev_for_path() {
  # Source device for exact path (empty if not mounted)
  local path="$1"
  findmnt -nr -T "$path" -o SOURCE 2>/dev/null || true
}

mounted_at() {
  # Where is this device mounted (if anywhere)
  local dev="$1"
  findmnt -nr -S "$dev" -o TARGET 2>/dev/null || true
}

dev_by_label() {
  local label="$1" p=""
  if have blkid; then
    p="$(blkid -L "$label" 2>/dev/null || true)"
    [[ -n "${p:-}" ]] && readlink -f -- "$p" && return 0
  fi
  p="$(lsblk -rpo NAME,LABEL 2>/dev/null | awk -v L="$label" '$2==L{print $1; exit}')"
  [[ -n "${p:-}" ]] && readlink -f -- "$p" && return 0
  return 1
}

bind_if_elsewhere() {
  local dev="$1" want="$2" cur
  cur="$(mounted_at "$dev")"
  if [[ -n "$cur" && "$cur" != "$want" ]]; then
    log "$dev already mounted at $cur; bind-mounting to $want"
    $SUDO mkdir -p -- "$want"
    $SUDO mount --bind "$cur" "$want"
    return 0
  fi
  return 1
}

ensure_one_mounted() {
  local label="$1" dev mnt fstype cur_dev
  dev="$(dev_by_label "$label")" || die "Could not find device with label $label"
  if [[ "$label" == "$BOOT_LABEL" ]]; then mnt="$BOOT_MOUNT"; fstype="vfat"; else mnt="$ROOT_MOUNT"; fstype="ext4"; fi

  # If exact path is already mounted on the right dev, done.
  if is_path_mounted "$mnt"; then
    cur_dev="$(src_dev_for_path "$mnt")"
    if [[ -n "$cur_dev" && "$cur_dev" == "$dev" ]]; then
      log "already mounted: $mnt"
      echo "$mnt"; return 0
    fi
    # Wrong backing dev at that path -> unmount quietly and continue
    log "remounting $mnt to correct device ($dev)"
    ($SUDO umount -R "$mnt" 2>/dev/null || $SUDO umount -Rl "$mnt" 2>/dev/null || true)
  fi

  # If device is mounted elsewhere, bind it
  if bind_if_elsewhere "$dev" "$mnt"; then
    echo "$mnt"; return 0
  fi

  # Fresh mount
  $SUDO mkdir -p -- "$mnt"
  log "mounting $label ($dev) -> $mnt"
  if ! $SUDO mount "$dev" "$mnt" 2>/dev/null; then
    $SUDO mount -t "$fstype" "$dev" "$mnt"
  fi
  echo "$mnt"
}

lazy_unmount_path() {
  local path="$1"
  if is_path_mounted "$path"; then
    log "unmounting $path"
    ($SUDO umount -R "$path" 2>/dev/null || $SUDO umount -Rl "$path" 2>/dev/null || true)
  fi
}

ensure-mounted() {
  log "ensure-mounted: $ROOT_LABEL -> $ROOT_MOUNT and $BOOT_LABEL -> $BOOT_MOUNT"
  ensure_one_mounted "$ROOT_LABEL" >/dev/null
  ensure_one_mounted "$BOOT_LABEL"  >/dev/null
  log "mounts:"
  findmnt -nr -o SOURCE,TARGET \
    | grep -E '(/mnt/sysclone-(boot|root))|(BOOT_MNJRO|ROOT_MNJRO)' \
    | sort -u || true
}

ensure-unmounted() {
  log "ensure-unmounted: $BOOT_MOUNT and $ROOT_MOUNT"
  lazy_unmount_path "$BOOT_MOUNT"
  lazy_unmount_path "$ROOT_MOUNT"

  # Also unmount any stray mountpoints for the labeled devices
  local dev t
  for L in "$BOOT_LABEL" "$ROOT_LABEL"; do
    if dev="$(dev_by_label "$L")"; then
      t="$(mounted_at "$dev")"
      if [[ -n "${t:-}" ]]; then
        log "unmounting $dev from $t"
        ($SUDO umount -R "$t" 2>/dev/null || $SUDO umount -Rl "$t" 2>/dev/null || true)
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
