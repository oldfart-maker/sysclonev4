#!/usr/bin/env bash
set -Eeuo pipefail
UNIT="tools/payloads/etc-systemd-system/sysclone-layer2-install.service"
[[ -f "$UNIT" ]] || { echo "[patch] missing $UNIT"; exit 1; }

# Ensure [Unit] has sane ordering; add or merge lines idempotently.
tmp="$UNIT.__new__"
awk '
  BEGIN{added=0}
  /^\[Unit\]$/ { print; print "After=network-online.target sysclone-net-bootstrap.service"; print "Wants=network-online.target sysclone-net-bootstrap.service"; print "Before=greetd.service"; added=1; next }
  /^After=/ && /sysclone-net-bootstrap\.service/ { found=1 }
  { print }
  END{ if(!added){} }
' "$UNIT" > "$tmp"

# If the file already had After/Wants/Before, de-dup them
sed -i -E \
  -e 's/^After=.*/After=network-online.target sysclone-net-bootstrap.service/' \
  -e 's/^Wants=.*/Wants=network-online.target sysclone-net-bootstrap.service/' \
  -e 's/^Before=.*/Before=greetd.service/' \
  "$tmp"

mv "$tmp" "$UNIT"
echo "[patch] updated ordering in $UNIT"
