#!/usr/bin/env bash
set -euo pipefail
f="tools/seed-first-boot-service.sh"
tmp="${f}.__new__"

# A) Insert a rootfs copy right after the BOOT install of sysclone-first-boot.sh (if not present)
awk '
  BEGIN{copied=0}
  {
    print
    if (!copied && $0 ~ /install/ && $0 ~ /sysclone-first-boot\.sh/ && ($0 ~ /BOOT_MOUNT|BOOT_MNT|\/mnt\/sysclone-boot/)) {
      print "sudo install -D -m 0755 \"${SRC_WIFI:-seeds/layer1/first-boot.sh}\" \\"
      print "  \"$ROOT_MOUNT/usr/local/sbin/sysclone-first-boot.sh\""
      copied=1
    }
  }
' "$f" > "$tmp" && mv "$tmp" "$f"

# B) Remove *any* line that would execute the script during seeding
#    (covers $SRC_WIFI, /usr/local/sbin/sysclone-first-boot.sh, /boot/sysclone-first-boot.sh)
tmp="${f}.__tmp__"
awk '
  {
    line=$0
    norm=line; gsub(/\t/," ",norm)
    if ( norm ~ /(^|[[:space:]])(bash|sh)?[[:space:]]*("?\$SRC_WIFI"?|\/usr\/local\/sbin\/sysclone-first-boot\.sh|\/boot\/sysclone-first-boot\.sh)([[:space:]]|$)/ ) {
      next
    }
    print
  }
' "$f" > "$tmp" && mv "$tmp" "$f"

chmod +x "$f"
echo "[sanitize] seeder now copies only; no host execution."
