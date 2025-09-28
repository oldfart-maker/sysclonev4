#!/usr/bin/env bash
set -euo pipefail
: "${ROOT_MNT:=/mnt/sysclone-root}"

sudo install -D -m 0644 tools/payloads/usr-local-share/sysclone-pi.mk \
  "${ROOT_MNT}/usr/local/share/sysclone/pi.mk"

sudo install -D -m 0755 tools/payloads/usr-local-bin/scpi \
  "${ROOT_MNT}/usr/local/bin/scpi"

echo "[pi-devtools] installed: /usr/local/share/sysclone/pi.mk and /usr/local/bin/scpi"
