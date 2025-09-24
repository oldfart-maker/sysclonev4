#!/usr/bin/env bash
set -euo pipefail
echo "[sanity] COMPOSITOR=$XDG_CURRENT_DESKTOP, WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}"
command -v sway >/dev/null 2>&1 && echo "[sanity] sway present"
command -v foot >/dev/null 2>&1 && echo "[sanity] foot present"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "[sanity] No Wayland session detected."
  echo "         On a TTY, log in as your user and run: start-sway"
fi
