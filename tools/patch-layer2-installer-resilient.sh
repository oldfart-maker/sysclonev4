#!/usr/bin/env bash
set -Eeuo pipefail

# Target payload script (template that gets copied to the Pi)
PAYLOAD="tools/payloads/usr-local-sbin/sysclone-layer2-install.sh"

[ -f "$PAYLOAD" ] || { echo "[patch] ERROR: $PAYLOAD not found"; exit 1; }

tmp="${PAYLOAD}.bak.$(date +%s)"
cp -a "$PAYLOAD" "$tmp"

# 1) Ensure a retry helper exists (idempotent)
if ! grep -q '^retry()' "$PAYLOAD"; then
  awk '
    BEGIN{added=0}
    {
      print $0
      if (!added && $0 ~ /^set -E/) {
        print "retry() { local n=0; until \"$@\"; do n=$((n+1)); [ $n -ge 3 ] && return 1; echo \"[retry] attempt $n failed; sleeping...\"; sleep 5; done; }"
        added=1
      }
    }' "$tmp" > "$PAYLOAD.__new__" && mv "$PAYLOAD.__new__" "$PAYLOAD"
fi

# 2) Force US HTTPS mirrors before big installs (idempotent)
if ! grep -q 'Force US https mirrors' "$PAYLOAD"; then
  # Insert just before the providers install step marker "07 providers"
  awk '
    /07 providers/ && !inserted {
      print "[layer2-install] 05b Force US https mirrors"
      print "pacman-mirrors --country United_States --protocol https --timeout 7 || true"
      print "pacman -Syy || true"
      inserted=1
    }
    { print $0 }
  ' "$PAYLOAD" > "$PAYLOAD.__new__" && mv "$PAYLOAD.__new__" "$PAYLOAD"
fi

# 3) Add --disable-download-timeout to pacman -S calls (idempotent)
sed -E -i 's/\bpacman\s+-S\b/pacman --disable-download-timeout -S/g' "$PAYLOAD"

# 4) Wrap the big provider/package installs with retry (idempotent best-effort)
# Only add "retry " to lines that *start* with pacman and do -S (avoid echo lines)
sed -E -i 's/^(\s*)(pacman --disable-download-timeout -S\b)/\1retry \2/' "$PAYLOAD"

echo "[patch] updated: $PAYLOAD (backup at $tmp)"
