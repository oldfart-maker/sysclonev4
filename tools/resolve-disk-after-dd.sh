#!/usr/bin/env bash
set -Eeuo pipefail
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"
TIMEOUT="${TIMEOUT:-60}"        # total seconds to try
SLEEP_INT="${SLEEP_INT:-0.5}"

have(){ command -v "$1" >/dev/null 2>&1; }
die(){ printf '[resolver] ERROR: %s\n' "$*" >&2; exit 1; }
log(){ printf '[resolver] %s\n' "$*"; }

# --- helpers ---------------------------------------------------------------

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

parent_disk() {
  local part="$1" p
  p="$(lsblk -nrpo PKNAME "$part" 2>/dev/null | head -n1)"
  [[ -z "$p" ]] && p="$(lsblk -nrpo NAME "$part" | sed -E 's/p?[0-9]+$//')"
  readlink -f -- "${p:-$part}"
}

# Heuristic: find a disk that has a small vfat (40M..1024M) + big ext4 partition.
# Prefer removable or USB devices; return the parent disk path.
heuristic_find_disk() {
  # list disks with their transport and removable flags
  # columns: NAME TYPE RM TRAN
  lsblk -nrpo NAME,TYPE,RM,TRAN 2>/dev/null | while read -r name type rm tran; do
    [[ "$type" != "disk" ]] && continue
    # skip system root disk heuristically if clearly non-removable and non-usb
    if [[ "$rm" != "1" && "$tran" != "usb" ]]; then
      # still consider mmc (SD slot) even if RM=0
      [[ "$name" =~ mmcblk ]] || continue
    fi
    # examine partitions
    local vfat_ok=0 ext4_ok=0
    while read -r p fs sz; do
      # fs TYPE, size in bytes
      if [[ "$fs" == "vfat" || "$fs" == "fat32" || "$fs" == "msdos" ]]; then
        # 40M..1024M
        if awk -v s="$sz" 'BEGIN{exit ! (s>=40*1024*1024 && s<=1024*1024*1024)}'; then
          vfat_ok=1
        fi
      elif [[ "$fs" == "ext4" ]]; then
        # bigger than 1G signals "root"
        if awk -v s="$sz" 'BEGIN{exit !(s>=1024*1024*1024)}'; then
          ext4_ok=1
        fi
      fi
    done < <(lsblk -nrbo NAME,FSTYPE,SIZE "$name" 2>/dev/null | awk '$2!=""{print $1,$2,$3}')
    if (( vfat_ok==1 && ext4_ok==1 )); then
      echo "$name"
      return 0
    fi
  done
  return 1
}

# --- main -----------------------------------------------------------------

main() {
  have udevadm && udevadm settle || true

  # First, try labels for up to half the TIMEOUT
  local t=0 limit; limit=$(awk -v T="$TIMEOUT" 'BEGIN{print (T>10?T/2:T)}')
  while (( $(printf '%.0f' "$t") < limit )); do
    if part="$(dev_by_label "$ROOT_LABEL")"; then parent_disk "$part"; return 0; fi
    if part="$(dev_by_label "$BOOT_LABEL")"; then parent_disk "$part"; return 0; fi
    sleep "$SLEEP_INT"; t=$(awk -v a="$t" -v b="$SLEEP_INT" 'BEGIN{print a+b}')
  done

  # Fallback: heuristic scan for typical RPi-style disk layout
  t=0
  while (( $(printf '%.0f' "$t") < TIMEOUT )); do
    if disk="$(heuristic_find_disk)"; then echo "$disk"; return 0; fi
    sleep "$SLEEP_INT"; t=$(awk -v a="$t" -v b="$SLEEP_INT" 'BEGIN{print a+b}')
  done

  # Final: print some diagnostics then fail
  lsblk -o NAME,TYPE,RM,TRAN,FSTYPE,LABEL,SIZE -r 1>&2 || true
  die "Unable to resolve SD disk by labels ($ROOT_LABEL/$BOOT_LABEL) or heuristic"
}

main "$@"
