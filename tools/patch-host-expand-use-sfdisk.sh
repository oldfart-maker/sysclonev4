#!/usr/bin/env bash
set -Eeuo pipefail
f="tools/host-expand-rootfs.sh"
b="$f.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$f" "$b"

# Replace the "resizing partition" block with sfdisk-first logic
awk '
BEGIN{printed=0}
{
  if (!printed && $0 ~ /^\s*# grow partition 2 to 100%/ ) {
    print $0
    getline   # skip the next line(s) that contained parted-only impl
    # emit sfdisk-first block
    print "log \"resizing partition 2 to 100% on $DEVICE\""
    print "if command -v sfdisk >/dev/null 2>&1; then"
    print "  log \"using sfdisk to expand partition 2\""
    print "  printf \",,+\\n\" | sfdisk -N 2 --no-reread --force \"$DEVICE\""
    print "elif command -v parted >/dev/null 2>&1; then"
    print "  log \"using parted to expand partition 2 (fallback)\""
    print "  parted -s \"$DEVICE\" ---pretend-input-tty <<CMD || true"
    print "unit %"
    print "print"
    print "resizepart 2 100%"
    print "Yes"
    print "print"
    print "CMD"
    print "else"
    print "  die \"no sfdisk/parted available\""
    print "fi"
    printed=1
    next
  }
  print
}
' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

echo "[patch] wrote $f (backup at $b)"
