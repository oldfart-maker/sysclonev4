#!/usr/bin/env bash
set -euo pipefail
f="tools/seed-layer1-network-bootstrap.sh"
[ -f "$f" ] || { echo "missing $f"; exit 1; }
bak="$f.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$f" "$bak"

awk '
  NR==1 && $0 ~ /^#!/ { print; next }
  NR==2 {
    print "require_target_mount(){"
    print "  ROOT_MNT=\"${ROOT_MNT:-/mnt/sysclone-root}\""
    print "  if ! mountpoint -q \"$ROOT_MNT\"; then"
    print "    echo \"[layer1] ERROR: $ROOT_MNT is not a mount (run: make ensure-mounted)\" >&2; exit 2"
    print "  fi"
    print "  if [ ! -d \"$ROOT_MNT/etc\" ]; then"
    print "    echo \"[layer1] ERROR: $ROOT_MNT doesn\\047t look like a Linux root (missing etc)\" >&2; exit 2"
    print "  fi"
    print "}"
    print "require_target_mount"
    print ""
  }
  { print }
' "$f" > "$f.new"

mv "$f.new" "$f"
chmod 0755 "$f"
echo "[guard] patched $f (backup at $bak)"
