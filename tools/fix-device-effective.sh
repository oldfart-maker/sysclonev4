#!/usr/bin/env bash
set -Eeuo pipefail
mf=Makefile
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

# 1) Ensure DEVICE_EFFECTIVE is defined once right after IMG_RAW :=
awk '
  /IMG_RAW *:=/ && !done {
    print
    print ""
    print "# Resolve DEVICE from cache if empty (works even if exported empty)"
    print "DEVICE_EFFECTIVE := $(or $(strip $(DEVICE)),$(shell test -f .cache/sysclonev4/last-device && cat .cache/sysclonev4/last-device))"
    done=1
    next
  }
  { print }
' "$mf" > "$mf.tmp" && mv "$mf.tmp" "$mf"

# 2) show-config: print DEVICE_EFFECTIVE
perl -0777 -pe 's/(^ \@echo "DEVICE\s+= )\$\((?:DEVICE)\)\("?\))/\1\$\((DEVICE_EFFECTIVE)\)\2/m' -i "$mf"

# 3) sd-write: require DEVICE_EFFECTIVE; dd uses DEVICE_EFFECTIVE
perl -0777 -pe 's/\[\s+-n\s+"\$\((?:DEVICE)\)"\s+\]\s+\|\|\s+\{ echo "Refusing: set DEVICE=\/dev\/sdX"; exit 2; \}/[ -n "$\(DEVICE_EFFECTIVE\)" ] || { echo "Refusing: set DEVICE=/dev/sdX (or use make DEVICE=/dev/sdX set-device)"; exit 2; }/m' -i "$mf"
perl -0777 -pe 's/of="\$\((?:DEVICE)\)"/of="$(DEVICE_EFFECTIVE)"/m' -i "$mf"

# 4) img-expand-rootfs-offline: echo + sudo env use DEVICE_EFFECTIVE
perl -0777 -pe 's/echo "\[make\] offline expand on \$\((?:DEVICE)\)"/echo "[make] offline expand on $(DEVICE_EFFECTIVE)"/m' -i "$mf"
perl -0777 -pe 's/sudo (?:env )?DEVICE=\$\((?:DEVICE)\) /sudo env DEVICE=$(DEVICE_EFFECTIVE) /m' -i "$mf"

echo "[fix] wrote $mf (backup at $bak)"
