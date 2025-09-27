#!/usr/bin/env bash
set -euo pipefail

in=tools/seed-first-boot-service.sh
out=${in}.__new__

# 1) Ensure we always install a real copy into rootfs (/usr/local/sbin)
#    We'll inject this copy step right after the first line that mentions copying to BOOT.
awk '
  BEGIN { injected=0 }
  {
    print $0
    if (!injected && $0 ~ /install.*sysclone-first-boot\.sh/ && $0 ~ /\/mnt\/sysclone-boot|BOOT_MOUNT|BOOT_MNT/) {
      print "sudo install -D -m 0755 \"$SRC_WIFI\" \"$ROOT_MOUNT/usr/local/sbin/sysclone-first-boot.sh\""
      injected=1
    }
  }
' "$in" > "$out"

mv "$out" "$in"

# 2) Remove ANY lines that would execute the script during seeding.
#    We match common forms: `$SRC_WIFI`, /usr/local/sbin/sysclone-first-boot.sh, /boot/sysclone-first-boot.sh
tmp=${in}.__tmp__
awk '
  BEGIN {
    drop=0
  }
  {
    line=$0
    # Normalize whitespace for matching
    gsub(/\t/," ", line)
    # If the line invokes the script (with or without bash/sh), drop it.
    if (line ~ /(^|[[:space:]])(bash|sh)?[[:space:]]*("?\$SRC_WIFI"?|\/usr\/local\/sbin\/sysclone-first-boot\.sh|\/boot\/sysclone-first-boot\.sh)([[:space:]]|$)/) {
      next
    }
    print $0
  }
' "$in" > "$tmp"
mv "$tmp" "$in"

# 3) Keep it executable
chmod +x "$in"
echo "[fix] seeder sanitized: copies script, does not execute it."
