#!/usr/bin/env bash
set -Eeuo pipefail
PI_MK="tools/payloads/usr-local-share/sysclone-pi.mk"
[[ -f "$PI_MK" ]] || { echo "[fix] missing $PI_MK"; exit 1; }

sed -i -E \
  -e 's/^verify-layer2\\\.5-install:/verify-layer2.5-install:/' \
  -e 's/^logs-layer2\\\.5:/logs-layer2.5:/' \
  -e 's/^rerun-layer2\\\.5-install:/rerun-layer2.5-install:/' \
  "$PI_MK"

echo "[fix] normalized .5 targets in $PI_MK"
