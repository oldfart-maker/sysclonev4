#!/usr/bin/env bash
set -euo pipefail
INS=tools/payloads/usr-local-sbin/sysclone-layer2-install.sh
[[ -f "$INS" ]] || { echo "missing $INS"; exit 2; }

# Replace l2_write_fallback_mirrorlist with a branch-aware, static-URL version
awk '
  BEGIN { replaced=0 }
  /l2_write_fallback_mirrorlist\(\)/ && !replaced { infunc=1; print; getline; 
    print "{";
    print "  # Detect Manjaro branch once (fallback to arm-unstable)";
    print "  local branch";
    print "  branch=$(awk -F= '"'"'/^Branch/ {gsub(/[ \"]/,\"\",$2); print $2}'"'"' /etc/pacman-mirrors.conf 2>/dev/null || true)";
    print "  branch=${branch:-arm-unstable}";
    print "  cat > /etc/pacman.d/mirrorlist <<ML";
    print "##";
    print "## Fallback mirrorlist (sysclone L2) with static branch";
    print "##";
    print "";
    print "Server = https://mirror.fcix.net/manjaro/"'"${branch}"'"/$repo/$arch";
    print "Server = https://ftp.halifax.rwth-aachen.de/manjaro/"'"${branch}"'"/$repo/$arch";
    print "Server = https://ftp.tsukuba.wide.ad.jp/Linux/manjaro/"'"${branch}"'"/$repo/$arch";
    print "ML";
    print "  echo \"[layer2-install] wrote fallback /etc/pacman.d/mirrorlist (branch=${branch})\"";
    print "}";
    infunc=0; replaced=1; next
  }
  infunc==1 { next }  # skip old function body
  { print }
' "$INS" > "$INS.__new__" && mv "$INS.__new__" "$INS"

# After the pacman-mirrors call (success or fallback), ensure DB refresh
# Insert a forced sync right after our echo lines if not already present.
grep -q 'l2_write_fallback_mirrorlist' "$INS" && \
  sed -i '/pacman-mirrors failed; using fallback/ a pacman -Syy --noconfirm || true' "$INS"
grep -q '\[layer2-install] pacman-mirrors ok' "$INS" && \
  sed -i '/\[layer2-install] pacman-mirrors ok/ a pacman -Syy --noconfirm || true' "$INS"

echo "[ok] patched fallback mirrorlist to embed static branch; added pacman -Syy"
