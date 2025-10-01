#!/usr/bin/env bash
set -Eeuo pipefail

f="seeds/layer3/seed-home.sh"
[[ -f "$f" ]] || { echo "[bake] ERROR: $f not found"; exit 1; }

# If we already bake, do nothing
if grep -q 'sed -i .*__HM_USER__' "$f"; then
  echo "[bake] already present; no changes"
  exit 0
fi

tmp="$(mktemp)"
awk '
  BEGIN { inserted=0 }
  # insert just before the chmod on the runner
  $0 ~ /^chmod[[:space:]]+0755[[:space:]]+"\$ROOT_MNT\/usr\/local\/sbin\/sysclone-layer3-home\.sh"[[:space:]]*$/ && !inserted {
    print "HM_BAKE_USER=\"${HM_USER:-${USERNAME:-username}}\""
    print "sed -i \"s/__HM_USER__/${HM_BAKE_USER//\\//\\/}/\" \\"
    print "  \"$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh\""
    inserted=1
  }
  { print }
  END {
    if (!inserted) {
      print "[bake] ERROR: could not find chmod line to anchor insertion" > "/dev/stderr"
      exit 2
    }
  }
' "$f" > "$tmp"

mv "$tmp" "$f"
echo "[bake] inserted sed replacement before chmod"
