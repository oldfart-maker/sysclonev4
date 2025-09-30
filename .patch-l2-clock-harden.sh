#!/usr/bin/env bash
set -euo pipefail

f="tools/payloads/usr-local-sbin/sysclone-layer2-install.sh"
tmp="$f.__new__"

awk '
  BEGIN{inserted=0}
  {print}
  # Insert immediately after the timesyncd enable/restart line (keeps patch resilient)
  $0 ~ /enable NTP .*timesyncd/ && !inserted {
    print " # --- Harden clock sync before touching TLS/mirrors ---"
    print " log \"03 wait for sane clock (<=300s, with HTTP bootstrap fallback)\""
    print " deadline=$(( $(date +%s) + 300 ))"
    print " synced=\"no\""
    print " while :; do"
    print "   if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q \"^yes$\"; then synced=\"yes\"; break; fi"
    print "   now=$(date +%s)"
    print "   if [ \"$now\" -ge 1704067200 ]; then break; fi  # >= 2024-01-01"
    print "   if command -v curl >/dev/null 2>&1; then"
    print "     http_date=\"$(curl -sI https://google.com | sed -n '\"'s/^Date: //p'\"')\""
    print "     if [ -n \"$http_date\" ] && sudo date -u -s \"$http_date\" >/dev/null 2>&1; then"
    print "       log \"03 bootstrapped clock from HTTP Date: $http_date\""
    print "     fi"
    print "   fi"
    print "   [ \"$(date +%s)\" -ge \"$deadline\" ] && break"
    print "   sleep 2"
    print " done"
    print " log \"03 clock ok (synced=$synced now=$(date +%s))\""
    print " # --- end clock hardening ---"
    inserted=1
  }
' "$f" > "$tmp"

# refuse to clobber if it was already inserted
if grep -q "Harden clock sync before touching TLS/mirrors" "$f"; then
  echo "[skip] block already present in $f"
  rm -f "$tmp"
else
  mv "$tmp" "$f"
  chmod +x "$f"
  echo "[ok] inserted clock-hardening block into $f"
fi
