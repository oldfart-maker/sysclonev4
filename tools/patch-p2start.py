#!/usr/bin/env python3
from pathlib import Path

p = Path("tools/host-expand-rootfs.sh")
s = p.read_text()

old = '''
  dump="$(sfdisk -d "$DEVICE")" || dump=""
  p2line="$(printf '%s\\n' "$dump" | awk -v dev="$DEVICE" '$1==dev "2" && $2==":" {print; exit}')" || p2line=""
  [ -n "$p2line" ] || die "could not locate ${DEVICE}2 in sfdisk dump"

  # parse start sector of p2
  p2start="$(printf '%s\\n' "$p2line" | awk '{
    for (i=1;i<=NF;i++) if ($i ~ /^start=/) { gsub(/start=|,/, "", $i); print $i; exit }
  }')" || true
  [ -n "$p2start" ] || die "failed to parse start for ${DEVICE}2"
'''.strip('\n')

new = '''
  dump="$(sfdisk -d "$DEVICE" 2>/dev/null || true)"
  p2start="$(printf '%s\\n' "$dump" | awk -v dev="$DEVICE" '
    BEGIN{s=""}
    $1==dev "2" && $2==":" {
      for (i=1;i<=NF;i++) if ($i ~ /^start=/) { gsub(/start=|,/, "", $i); s=$i; break }
      if (s!="") { print s; exit }
    }')"
  # Fallback: parted (machine-readable), unit sectors
  if [ -z "$p2start" ]; then
    p2start="$(parted -sm "$DEVICE" unit s print 2>/dev/null \
      | awk -F: '$1=="2"{ gsub(/s$/,"",$2); print $2; exit }')"
  fi
  [ -n "$p2start" ] || die "failed to parse start for ${DEVICE}2"
'''.strip('\n')

if old not in s:
    raise SystemExit("Expected p2start block not found—file drifted from known layout.")
s = s.replace(old, new)
p.write_text(s)
print("[patch] p2start now parsed via sfdisk with parted fallback")
