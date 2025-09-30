#!/usr/bin/env bash
set -Eeuo pipefail
mf="Makefile"
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

# --- Ensure DEVICE_EFFECTIVE is defined once right after IMG_RAW := ---
if ! grep -qE '^[[:space:]]*DEVICE_EFFECTIVE[[:space:]]*:=' "$mf"; then
  awk '
    /IMG_RAW[[:space:]]*:=/ && !done {
      print
      print ""
      print "# Resolve DEVICE from cache if empty (works even if exported empty)"
      print "DEVICE_EFFECTIVE := $(or $(strip $(DEVICE)),$(shell test -f .cache/sysclonev4/last-device && cat .cache/sysclonev4/last-device))"
      done=1; next
    }
    { print }
  ' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"
fi

# --- Fix show-config line for DEVICE (replace the whole echo line safely) ---
awk '
  BEGIN { fixed=0 }
  {
    if ($0 ~ /^[[:space:]]*@echo "DEVICE[[:space:]]*=/ && !fixed) {
      print "\t@echo \"DEVICE     = $(DEVICE_EFFECTIVE)\""
      fixed=1
      next
    }
    print
  }
' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

# --- Make sd-write use DEVICE_EFFECTIVE (guard + dd target) ---
# guard line
sed -i 's/\[ -n "\$(DEVICE)" ] || { echo "Refusing: set DEVICE=\/dev\/sdX"; exit 2; }/[ -n "$(DEVICE_EFFECTIVE)" ] || { echo "Refusing: set DEVICE=\/dev\/sdX (or use make DEVICE=\/dev\/sdX set-device)"; exit 2; }/' "$mf"
# dd target
sed -i 's/of="\$(DEVICE)"/of="$(DEVICE_EFFECTIVE)"/' "$mf"

# --- Make img-expand-rootfs-offline echo & sudo pass DEVICE_EFFECTIVE ---
awk '
  BEGIN { in=0 }
  /^img-expand-rootfs-offline:[[:space:]]/ { print; in=1; next }
  in==1 && $0 ~ /^[^ \t]/ { in=0 }   # next target begins
  {
    if (in==1) {
      # echo line (replace string inside quotes)
      if ($0 ~ /\[make\] offline expand on /) {
        print "\t@echo \"[make] offline expand on $(DEVICE_EFFECTIVE)\""
        next
      }
      # sudo invocation: normalize to sudo env DEVICE=$(DEVICE_EFFECTIVE) ...
      if ($0 ~ /host-expand-rootfs\.sh/ ) {
        print "\t@sudo env DEVICE=$(DEVICE_EFFECTIVE) ROOT_MNT=$(ROOT_MNT) BOOT_MNT=$(BOOT_MNT) tools/host-expand-rootfs.sh"
        next
      }
    }
    print
  }
' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

echo "[fix-device] wrote $mf (backup at $bak)"
