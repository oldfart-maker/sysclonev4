#!/usr/bin/env python3
import re, shutil, sys
p = "tools/host-expand-rootfs.sh"
bak = p + ".bak"
shutil.copyfile(p, bak)

with open(p, "r", encoding="utf-8") as f:
    s = f.read()

pattern = re.compile(
    r'(?ms)^log "resizing partition 2 to 100% on \$DEVICE"\n.*?\n(?=^# re-read table)',
    re.M | re.S,
)

replacement = '''log "resizing partition 2 to 100% on $DEVICE"
# capture current p2 size to detect change later
old_sz="$(blockdev --getsz "${DEVICE}2" 2>/dev/null || echo 0)"

if command -v sfdisk >/dev/null 2>&1; then
  log "using sfdisk dump+rewrite to grow p2 with explicit size; keep type 83; avoid reread hang"
  dump="$(sfdisk -d "$DEVICE")" || dump=""
  p2line="$(printf '%s\\n' "$dump" | awk -v dev="$DEVICE" '$1==dev "2" && $2==":" {print; exit}')" || p2line=""
  [ -n "$p2line" ] || die "could not locate ${DEVICE}2 in sfdisk dump"

  # parse start sector of p2
  p2start="$(printf '%s\\n' "$p2line" | awk '{
    for (i=1;i<=NF;i++) if ($i ~ /^start=/) { gsub(/start=|,/, "", $i); print $i; exit }
  }')" || true
  [ -n "$p2start" ] || die "failed to parse start for ${DEVICE}2"

  # compute total sectors and target size (end to last sector)
  total="$(blockdev --getsz "$DEVICE" || true)"
  [ -n "$total" ] || die "failed to read total sectors for $DEVICE"
  newsize="$(( total - p2start ))"
  [ "$newsize" -gt 0 ] || die "computed non-positive size for ${DEVICE}2 (total=$total start=$p2start)"

  # rewrite p2 explicitly with same start, explicit size, and Linux type (0x83)
  printf "%s : start= %s, size= %s, type=83\\n" "${DEVICE}2" "$p2start" "$newsize" \
    | sfdisk --no-reread --force "$DEVICE"

elif command -v parted >/dev/null 2>&1; then
  log "using parted to expand partition 2 (fallback)"
  parted -s "$DEVICE" ---pretend-input-tty <<CMD || true
unit %
print
resizepart 2 100%
Yes
print
CMD
else
  die "no sfdisk/parted available"
fi

# refresh kernel view of the new table
log "refreshing kernel partition table (partprobe/partx) and udev"
partprobe "$DEVICE" || true
partx -u "$DEVICE" || true
udevadm settle || true
sleep 1

# verify growth; fail loudly if unchanged
new_sz="$(blockdev --getsz "${DEVICE}2" 2>/dev/null || echo 0)"
log "p2 sectors: old=$old_sz new=$new_sz (device total=$(blockdev --getsz "$DEVICE" || echo ?))"
[ "$new_sz" -gt "$old_sz" ] || die "p2 did not grow (old=$old_sz new=$new_sz)"

'''
ns, n = pattern.subn(replacement, s)
if n == 0:
    sys.exit("did not find the grow block to replace (start marker missing?)")
with open(p, "w", encoding="utf-8") as f:
    f.write(ns)
print(f"[fix-grow] updated {p} (backup at {bak})")
