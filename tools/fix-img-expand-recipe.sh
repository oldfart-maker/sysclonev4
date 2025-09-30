#!/usr/bin/env bash
set -Eeuo pipefail
mf="Makefile"
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

perl -0777 -pe '
  s/^
     (img\-expand\-rootfs\-offline:[^\n]*\n)   # capture the exact header line
     (?:[ \t].*\n)+?                           # existing indented recipe lines (one or more)
   /
     $1 .
     "\t\@echo \"[make] offline expand on \$(DEVICE_EFFECTIVE)\"\n" .
     "\t\@sudo env DEVICE=\$(DEVICE_EFFECTIVE) ROOT_MNT=\$(ROOT_MNT) BOOT_MNT=\$(BOOT_MNT) tools/host-expand-rootfs.sh\n"
  /gmx
' -i "$mf"

echo "[fix] rewrote only img-expand-rootfs-offline recipe (backup at $bak)"
