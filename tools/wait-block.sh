#!/usr/bin/env bash
# usage:
#   tools/wait-block.sh /dev/sdX [--need-p2]
# waits until /dev/sdX is a block device; if --need-p2 is given,
# also waits for partition 2 to exist (handles nvme/mmc "p" suffix).
set -Eeuo pipefail
DEV="${1:-}"; NEED_P2="${2:-}"
[[ -n "$DEV" ]] || { echo "[wait] usage: $0 /dev/sdX [--need-p2]" >&2; exit 2; }
TIMEOUT="${TIMEOUT:-30}"   # seconds
SLEEP="${SLEEP:-0.25}"     # seconds
# attempts = floor(TIMEOUT/SLEEP)+1
ITERS="$(awk -v T="$TIMEOUT" -v S="$SLEEP" 'BEGIN{ if (S<=0) S=0.25; print int(T/S)+1 }')"

for _ in $(seq 1 "$ITERS"); do
  if [[ -b "$DEV" ]]; then
    if [[ "$NEED_P2" == "--need-p2" ]]; then
      suf=""; case "$DEV" in *mmcblk*|*nvme*) suf="p";; esac
      if [[ -b "${DEV}${suf}2" ]]; then
        echo "$DEV"; exit 0
      fi
    else
      echo "$DEV"; exit 0
    fi
  fi
  # try to help the kernel/userspace settle
  command -v udevadm >/dev/null && udevadm settle || true
  command -v partprobe >/dev/null && partprobe "$DEV" 2>/dev/null || true
  sleep "$SLEEP"
done
echo "[wait] ERROR: $DEV not ready within ${TIMEOUT}s" >&2
exit 1
