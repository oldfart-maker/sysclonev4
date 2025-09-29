#!/usr/bin/env bash
# Resolve the SD card *disk* node deterministically after imaging.
# Priority:
# 1) If a DEVICE is given, use /dev/disk/by-path (stable) for that device.
# 2) Fallback to /dev/disk/by-id for that device.
# 3) Fallback to labels (BOOT/ROOT), then layout heuristic (vfat+ext4).
set -Eeuo pipefail

PREFER_DEVICE=""
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"
TIMEOUT="${TIMEOUT:-60}"
SLEEP_INT="${SLEEP_INT:-0.5}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefer-device) PREFER_DEVICE="$2"; shift 2;;
    --boot-label) BOOT_LABEL="$2"; shift 2;;
    --root-label) ROOT_LABEL="$2"; shift 2;;
    *) echo "[resolver] unknown arg: $1" >&2; exit 2;;
  esac
done

have(){ command -v "$1" >/dev/null 2>&1; }
norm_disk(){
  # Given a path to a disk or partition, return the *disk* path (no partition suffix)
  local d="$1"; d="$(readlink -f -- "$d" 2>/dev/null || true)"
  [[ -z "$d" ]] && return 1
  # strip partition suffix (handles sdX#, nvme0n1p#, mmcblk0p#)
  local base; base="$(basename "$d")"
  if [[ "$base" =~ ^(nvme|mmcblk) ]]; then
    d="/dev/${base%p[0-9]*}"
  else
    d="/dev/${base%%[0-9]*}"
  fi
  readlink -f -- "$d"
}
by_path_key_for_disk(){
  # Find a by-path symlink that points to this disk
  local disk="$1" p tgt
  for p in /dev/disk/by-path/*; do
    [[ -e "$p" ]] || continue
    tgt="$(readlink -f -- "$p" 2>/dev/null || true)"
    [[ "$tgt" == "$disk" ]] && { basename "$p"; return 0; }
  done
  return 1
}
by_id_key_for_disk(){
  local disk="$1" p tgt
  for p in /dev/disk/by-id/*; do
    [[ -e "$p" ]] || continue
    tgt="$(readlink -f -- "$p" 2>/dev/null || true)"
    [[ "$tgt" == "$disk" ]] && { basename "$p"; return 0; }
  done
  return 1
}
resolve_via_key(){
  local dir="$1" key="$2" t=0 tgt=""
  have udevadm && udevadm settle || true
  while (( $(printf '%.0f' "$t") < TIMEOUT )); do
    [[ -L "$dir/$key" ]] && tgt="$(readlink -f -- "$dir/$key" 2>/dev/null || true)" || true
    if [[ -n "$tgt" && -b "$tgt" ]]; then echo "$tgt"; return 0; fi
    sleep "$SLEEP_INT"; t=$(awk -v a="$t" -v b="$SLEEP_INT" 'BEGIN{print a+b}')
  done
  return 1
}
dev_by_label(){
  local label="$1" p=""
  if have blkid; then
    p="$(blkid -L "$label" 2>/dev/null || true)"
    [[ -n "$p" ]] && readlink -f -- "$p" && return 0
  fi
  p="$(lsblk -rpo NAME,LABEL 2>/dev/null | awk -v L="$label" '$2==L{print $1; exit}')"
  [[ -n "$p" ]] && readlink -f -- "$p" && return 0
  return 1
}
parent_disk(){
  local part="$1" p
  p="$(lsblk -nrpo PKNAME "$part" 2>/dev/null | head -n1)"
  [[ -z "$p" ]] && p="$(lsblk -nrpo NAME "$part" | sed -E 's/p?[0-9]+$//')"
  readlink -f -- "${p:-$part}"
}
heuristic_find_disk(){
  lsblk -nrpo NAME,TYPE,RM,TRAN 2>/dev/null | while read -r name type rm tran; do
    [[ "$type" != "disk" ]] && continue
    # Prefer removable/usb/mmc, but allow others if signature matches
    local vfat_ok=0 ext4_ok=0
    while read -r p fs sz; do
      [[ -z "$fs" ]] && continue
      if [[ "$fs" =~ ^(vfat|fat32|msdos)$ ]]; then
        # 32M..2G to be generous
        if awk -v s="$sz" 'BEGIN{exit ! (s>=32*1024*1024 && s<=2*1024*1024*1024)}'; then vfat_ok=1; fi
      elif [[ "$fs" == "ext4" ]]; then
        if awk -v s="$sz" 'BEGIN{exit !(s>=1024*1024*1024)}'; then ext4_ok=1; fi
      fi
    done < <(lsblk -nrbo NAME,FSTYPE,SIZE "$name" 2>/dev/null)
    (( vfat_ok && ext4_ok )) && { echo "$name"; return 0; }
  done
  return 1
}

main(){
  local disk="" key=""
  have udevadm && udevadm settle || true

  if [[ -n "$PREFER_DEVICE" ]]; then
    local base; base="$(norm_disk "$PREFER_DEVICE" 2>/dev/null || true)"
    if [[ -n "$base" && -b "$base" ]]; then
      # Try by-path first
      if key="$(by_path_key_for_disk "$base" 2>/dev/null || true)"; then
        if disk="$(resolve_via_key "/dev/disk/by-path" "$key")"; then echo "$disk"; return 0; fi
      fi
      # Fallback to by-id
      if key="$(by_id_key_for_disk "$base" 2>/dev/null || true)"; then
        if disk="$(resolve_via_key "/dev/disk/by-id" "$key")"; then echo "$disk"; return 0; fi
      fi
    fi
  fi

  # Labels (if present quickly)
  local part=""
  local t=0; while (( $(printf '%.0f' "$t") < TIMEOUT/2 )); do
    if part="$(dev_by_label "$ROOT_LABEL")"; then echo "$(parent_disk "$part")"; return 0; fi
    if part="$(dev_by_label "$BOOT_LABEL")"; then echo "$(parent_disk "$part")"; return 0; fi
    sleep "$SLEEP_INT"; t=$(awk -v a="$t" -v b="$SLEEP_INT" 'BEGIN{print a+b}')
  done

  # Heuristic layout fallback
  if disk="$(heuristic_find_disk)"; then echo "$disk"; return 0; fi

  # Diagnostics then fail
  lsblk -o NAME,TYPE,RM,TRAN,FSTYPE,LABEL,SIZE -r 1>&2 || true
  echo "[resolver] INFO: by-path keys for $PREFER_DEVICE:" 1>&2
  ls -l /dev/disk/by-path 1>&2 || true
  echo "[resolver] INFO: by-id keys for $PREFER_DEVICE:" 1>&2
  ls -l /dev/disk/by-id 1>&2 || true
  echo "[resolver] ERROR: could not resolve disk" 1>&2
  exit 1
}
main
