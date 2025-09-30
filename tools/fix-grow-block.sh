#!/usr/bin/env bash
set -Eeuo pipefail
f="tools/host-expand-rootfs.sh"
bak="$f.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$f" "$bak"

# Replace lines from:
#   log "resizing partition 2 to 100% on $DEVICE"
# up to (but not including) the line:
#   # re-read table
ed -s "$f" <<'ED'
/^log "resizing partition 2 to 100% on \$DEVICE"/,/^# re-read table/-1c
log "resizing partition 2 to 100% on $DEVICE"
# capture current p2 size to detect change later
old_sz="$(blockdev --getsz "${DEVICE}2" 2>/dev/null || echo 0)"

if command -v sfdisk >/dev/null 2>&1; then
  log "using sfdisk dump+rewrite to grow p2 with explicit size; keep type 83; avoid reread hang"
  dump="$(sfdisk -d "$DEVICE")" || dump=""
  p2line="$(printf '%s\n' "$dump" | awk -v dev="$DEVICE" '$1==dev "2" && $2==":" {print; exit}')" || p2line=""
  [ -n "$p2line" ] || die "could not locate ${DEVICE}2 in sfdisk dump"

  # parse start sector of p2
  p2start="$(printf '%s\n' "$p2line" | awk '{
    for (i=1;i<=NF;i++) if ($i ~ /^start=/) { gsub(/start=|,/, "", $i); print $i; exit }
  }')" || true
  [ -n "$p2start" ] || die "failed to parse start for ${DEVICE}2"

  # compute total sectors and target size (end to last sector)
  total="$(blockdev --getsz "$DEVICE" || true)"
  [ -n "$total" ] || die "failed to read total sectors for $DEVICE"
  newsize="$(( total - p2start ))"
  [ "$newsize" -gt 0 ] || die "computed non-positive size for ${DEVICE}2 (total=$total start=$p2start)"

  # rewrite p2 explicitly with same start, explicit size, and Linux type (0x83)
  printf "%s : start= %s, size= %s, type=83\n" "${DEVICE}2" "$p2start" "$newsize" \
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
.
wq
ED

echo "[fix-grow] updated $f (backup at $bak)"
