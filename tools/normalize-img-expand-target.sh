#!/usr/bin/env bash
set -Eeuo pipefail
mf=Makefile
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

awk '
  BEGIN { in=0 }
  # When we see the target header, print it and our canonical recipe
  /^img-expand-rootfs-offline:[[:space:]]*/ {
    print $0
    print "\t@echo \"[make] offline expand on $(DEVICE_EFFECTIVE)\""
    print "\t@sudo env DEVICE=$(DEVICE_EFFECTIVE) ROOT_MNT=$(ROOT_MNT) BOOT_MNT=$(BOOT_MNT) tools/host-expand-rootfs.sh"
    in=1
    next
  }
  # While inside the old recipe, skip lines until the next non-indented (new target or blank)
  in==1 {
    if ($0 ~ /^[^ \t]/) { in=0; print $0 }  # next target/declaration starts
    next
  }
  { print }
' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

echo "[normalize] rewrote img-expand-rootfs-offline recipe (backup at $bak)"
