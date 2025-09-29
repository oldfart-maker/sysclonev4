#!/usr/bin/env bash
# Usage: DEVICE_BY_PATH=/dev/disk/by-path/... tools/resolve-by-path-now.sh
set -Eeuo pipefail
: "${DEVICE_BY_PATH:?set DEVICE_BY_PATH to /dev/disk/by-path/...}"
TIMEOUT="${TIMEOUT:-30}"   # seconds (can be float)
SLEEP="${SLEEP:-0.25}"     # seconds (can be float)

have(){ command -v "$1" >/dev/null 2>&1; }

# Compute how many attempts to make (avoid float arithmetic in bash)
iters="$(awk -v T="$TIMEOUT" -v S="$SLEEP" 'BEGIN{ if (S<=0) S=0.25; print int(T/S)+1 }')"

for _ in $(seq 1 "$iters"); do
  have udevadm && udevadm settle || true
  DEV="$(readlink -f -- "$DEVICE_BY_PATH" 2>/dev/null || true)"
  if [[ -n "$DEV" && -b "$DEV" ]]; then
    printf '%s\n' "$DEV"
    exit 0
  fi
  sleep "$SLEEP"
done

echo "[resolve] ERROR: no block device for $DEVICE_BY_PATH within ${TIMEOUT}s" >&2
exit 1
