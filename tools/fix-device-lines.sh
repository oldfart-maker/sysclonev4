#!/usr/bin/env bash
set -Eeuo pipefail
mf=Makefile
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

# 1) Define DEVICE_EFFECTIVE once, right after IMG_RAW := (if missing)
grep -q '^DEVICE_EFFECTIVE *:=' "$mf" || awk '
  /IMG_RAW *:=/ && !done {
    print
    print ""
    print "# Resolve DEVICE from cache if empty (works even if exported empty)"
    print "DEVICE_EFFECTIVE := $(or $(strip $(DEVICE)),$(shell test -f .cache/sysclonev4/last-device && cat .cache/sysclonev4/last-device))"
    done=1; next
  }
  { print }
' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

# 2) Fix show-config DEVICE echo to use DEVICE_EFFECTIVE (replace the entire line)
#    Match the line that begins with a tab + @echo "DEVICE     =
awk '
  BEGIN{fixed=0}
  {
    if ($0 ~ /^\t@echo "DEVICE[[:space:]]+=/) {
      if (!fixed) {
        print "\t@echo \"DEVICE     = $(DEVICE_EFFECTIVE)\""
        fixed=1
        next
      }
    }
    print
  }
' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

# 3) Update img-expand-rootfs-offline recipe to use DEVICE_EFFECTIVE and sudo env
#    Replace only within that target's recipe block.
awk '
  BEGIN{in_tgt=0}
  /^img-expand-rootfs-offline:[[:space:]]/ {print; in_tgt=1; next}
  in_tgt==1 && $0 ~ /^[^ \t]/ {in_tgt=0}  # next target starts
  {
    if (in_tgt==1) {
      # echo line
      gsub(/\[make\] offline expand on .*/, "[make] offline expand on $(DEVICE_EFFECTIVE)")
      # sudo line: ensure it is sudo env DEVICE=$(DEVICE_EFFECTIVE) ...
      sub(/sudo .*tools\/host-expand-rootfs\.sh/, "sudo env DEVICE=$(DEVICE_EFFECTIVE) ROOT_MNT=$(ROOT_MNT) BOOT_MNT=$(BOOT_MNT) tools/host-expand-rootfs.sh")
      print
      next
    }
    print
  }
' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

echo "[fix] wrote $mf (backup at $bak)"
