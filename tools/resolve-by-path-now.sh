#!/usr/bin/env bash
# Usage: DEVICE_BY_PATH=/dev/disk/by-path/... tools/resolve-by-path-now.sh
set -Eeuo pipefail
: "${DEVICE_BY_PATH:?set DEVICE_BY_PATH to /dev/disk/by-path/...}"
TIMEOUT="${TIMEOUT:-30}"
SLEEP="${SLEEP:-0.25}"

have(){ command -v "$1" >/dev/null 2>&1; }

t=0
while :; do
  have udevadm && udevadm settle || true
  DEV="$(readlink -f -- "$DEVICE_BY_PATH" 2>/dev/null || true)"
  if [[ -n "$DEV" && -b "$DEV" ]]; then
    printf '%s\n' "$DEV"
    exit 0
  fi
  (( t >= TIMEOUT )) && { echo "[resolve] ERROR: no block device for $DEVICE_BY_PATH" >&2; exit 1; }
  sleep "$SLEEP"
  t=$(awk -v a="$t" -v b="$SLEEP" 'BEGIN{print a+b}')
done
