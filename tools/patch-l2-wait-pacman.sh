#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT="tools/payloads/usr-local-sbin/sysclone-layer2-install.sh"
[[ -f "$SCRIPT" ]] || { echo "[patch] missing $SCRIPT"; exit 1; }

# Add wait_pacman() once
grep -q 'wait_pacman()' "$SCRIPT" || {
  tmp="$SCRIPT.__new__"
  awk '
    NR==1{ print; print ""; print "wait_pacman() {"; print "  local t=0;"; print "  while [[ -e /var/lib/pacman/db.lck ]] || pgrep -x pacman >/dev/null; do"; print "    ((t++)); if (( t>300 )); then echo \"[layer2-install] timeout waiting for pacman lock\"; return 1; fi"; print "    sleep 1;"; print "  done"; print "}"; print ""; next }
    { print }
  ' "$SCRIPT" > "$tmp"
  mv "$tmp" "$SCRIPT"
}

# Prepend wait_pacman before common pacman operations (idempotent)
sed -i -E '
  /(^|[;])\s*pacman(\s|$)/i wait_pacman || exit 1
  /(^|[;])\s*pacman-mirrors(\s|$)/i wait_pacman || exit 1
' "$SCRIPT"

echo "[patch] added wait_pacman and guarded pacman calls in $SCRIPT"
