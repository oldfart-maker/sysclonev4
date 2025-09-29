#!/usr/bin/env bash
set -Eeuo pipefail
DEVICE="${DEVICE:-}"
OUT="${OUT:-cache/disk-key.env}"
[[ -n "$DEVICE" ]] || { echo "[capture] ERROR: DEVICE not set" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

norm_disk(){ local d="$1"; d="$(readlink -f -- "$d" 2>/dev/null || true)"; [[ -z "$d" ]] && return 1
  local b; b="$(basename "$d")"
  if [[ "$b" =~ ^(nvme|mmcblk) ]]; then echo "/dev/${b%p[0-9]*}"; else echo "/dev/${b%%[0-9]*}"; fi; }

disk="$(norm_disk "$DEVICE")"
[[ -b "$disk" ]] || { echo "[capture] ERROR: not a block disk: $disk" >&2; exit 1; }

by_path=""; by_id=""
for p in /dev/disk/by-path/*; do
  [[ -e "$p" ]] || continue
  [[ "$(readlink -f -- "$p")" == "$disk" ]] && { by_path="$(basename "$p")"; break; }
done
if [[ -z "$by_path" ]]; then
  for p in /dev/disk/by-id/*; do
    [[ -e "$p" ]] || continue
    [[ "$(readlink -f -- "$p")" == "$disk" ]] && { by_id="$(basename "$p")"; break; }
  done
fi

{
  echo "# captured $(date -Is)"
  echo "DISK_CAPTURED=\"$disk\""
  if [[ -n "$by_path" ]]; then
    echo "KEY_DIR=\"/dev/disk/by-path\""
    echo "KEY_NAME=\"$by_path\""
  elif [[ -n "$by_id" ]]; then
    echo "KEY_DIR=\"/dev/disk/by-id\""
    echo "KEY_NAME=\"$by_id\""
  else
    echo "KEY_DIR="
    echo "KEY_NAME="
  fi
} > "$OUT"

echo "[capture] wrote $OUT"
[[ -s "$OUT" ]] || { echo "[capture] ERROR: failed to write $OUT" >&2; exit 1; }
