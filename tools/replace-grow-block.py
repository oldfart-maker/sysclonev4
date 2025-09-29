#!/usr/bin/env python3
from pathlib import Path

p = Path("tools/host-expand-rootfs.sh")
s = p.read_text()

start_marker = 'log "resizing partition 2 to 100% on $DEVICE"'
end_marker   = '# refresh kernel view of the new table'

start = s.find(start_marker)
if start == -1:
    raise SystemExit("start grow marker not found")

end = s.find(end_marker, start)
if end == -1:
    raise SystemExit("end grow marker not found")

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
  printf "%s : start= %s, size= %s, type=83\\n" "${DEVICE}2" "$p2start" "$newsize" | \
    sfdisk --no-reread --force "$DEVICE"

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
'''

bak = p.with_suffix(".sh.bak")
bak.write_text(s)
p.write_text(s[:start] + replacement + s[end:])

print(f"[replace-grow] updated {p} (backup at {bak})")
