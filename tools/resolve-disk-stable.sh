#!/usr/bin/env bash
set -Eeuo pipefail
KEY_FILE="${KEY_FILE:-cache/disk-key.env}"
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"
TIMEOUT="${TIMEOUT:-60}"
SLEEP_INT="${SLEEP_INT:-0.5}"
PREFER_DEVICE="${PREFER_DEVICE:-}"

have(){ command -v "$1" >/dev/null 2>&1; }
norm_disk(){ local d="$1"; d="$(readlink -f -- "$d" 2>/dev/null || true)"; [[ -z "$d" ]] && return 1
  local b; b="$(basename "$d")"
  if [[ "$b" =~ ^(nvme|mmcblk) ]]; then echo "/dev/${b%p[0-9]*}"; else echo "/dev/${b%%[0-9]*}"; fi; }
resolve_via_key(){ local dir="$1" key="$2" t=0 tgt=""
  have udevadm && udevadm settle || true
  while (( $(printf '%.0f' "$t") < TIMEOUT )); do
    [[ -L "$dir/$key" ]] && tgt="$(readlink -f -- "$dir/$key" 2>/dev/null || true)" || true
    if [[ -n "$tgt" && -b "$tgt" ]]; then echo "$tgt"; return 0; fi
    sleep "$SLEEP_INT"; t=$(awk -v a="$t" -v b="$SLEEP_INT" 'BEGIN{print a+b}')
  done; return 1; }
dev_by_label(){ local L="$1" p=""
  if have blkid; then p="$(blkid -L "$L" 2>/dev/null || true)"; [[ -n "$p" ]] && readlink -f -- "$p" && return 0; fi
  p="$(lsblk -rpo NAME,LABEL 2>/dev/null | awk -v X="$L" '$2==X{print $1; exit}')"
  [[ -n "$p" ]] && readlink -f -- "$p" && return 0; return 1; }
parent_disk(){ local part="$1" p
  p="$(lsblk -nrpo PKNAME "$part" 2>/dev/null | head -n1)"; [[ -z "$p" ]] && p="$(lsblk -nrpo NAME "$part" | sed -E 's/p?[0-9]+$//')"
  readlink -f -- "${p:-$part}"; }
heuristic_find_disk(){ lsblk -nrpo NAME,TYPE 2>/dev/null | while read -r name type; do
    [[ "$type" != "disk" ]] && continue
    local vfat_ok=0 ext4_ok=0
    while read -r p fs sz; do
      [[ -z "$fs" ]] && continue
      if [[ "$fs" =~ ^(vfat|fat32|msdos)$ ]]; then
        if awk -v s="$sz" 'BEGIN{exit ! (s>=32*1024*1024 && s<=2*1024*1024*1024)}'; then vfat_ok=1; fi
      elif [[ "$fs" == "ext4" ]]; then
        if awk -v s="$sz" 'BEGIN{exit !(s>=1024*1024*1024)}'; then ext4_ok=1; fi
      fi
    done < <(lsblk -nrbo NAME,FSTYPE,SIZE "$name" 2>/dev/null)
    (( vfat_ok && ext4_ok )) && { echo "$name"; return 0; }
  done; return 1; }

main(){
  have udevadm && udevadm settle || true

  # 0) If a device was provided, try to derive a live by-path/by-id key NOW.
  if [[ -n "$PREFER_DEVICE" ]]; then
    base="$(norm_disk "$PREFER_DEVICE" 2>/dev/null || true)"
    if [[ -n "$base" && -b "$base" ]]; then
      for p in /dev/disk/by-path/*; do [[ -e "$p" ]] || continue; [[ "$(readlink -f -- "$p")" == "$base" ]] && echo "$(readlink -f -- "$p")" && return 0; done
      for p in /dev/disk/by-id/*;   do [[ -e "$p" ]] || continue; [[ "$(readlink -f -- "$p")" == "$base" ]] && echo "$(readlink -f -- "$p")" && return 0; done
    fi
  fi

  # 1) Use captured key if available
  if [[ -f "$KEY_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$KEY_FILE" || true
    if [[ -n "${KEY_DIR:-}" && -n "${KEY_NAME:-}" ]]; then
      if disk="$(resolve_via_key "$KEY_DIR" "$KEY_NAME")"; then echo "$disk"; return 0; fi
    fi
  fi

  # 2) Try labels briefly
  local t=0 part=""
  while (( $(printf '%.0f' "$t") < TIMEOUT/2 )); do
    if part="$(dev_by_label "$ROOT_LABEL")"; then echo "$(parent_disk "$part")"; return 0; fi
    if part="$(dev_by_label "$BOOT_LABEL")"; then echo "$(parent_disk "$part")"; return 0; fi
    sleep "$SLEEP_INT"; t=$(awk -v a="$t" -v b="$SLEEP_INT" 'BEGIN{print a+b}')
  done

  # 3) Heuristic signature
  if disk="$(heuristic_find_disk)"; then echo "$disk"; return 0; fi

  # Diagnostics
  ls -l /dev/disk/by-path 1>&2 || true
  ls -l /dev/disk/by-id   1>&2 || true
  lsblk -o NAME,TYPE,RM,TRAN,FSTYPE,LABEL,SIZE -r 1>&2 || true
  echo "[resolver] ERROR: could not resolve disk" >&2
  exit 1
}
main "$@"
