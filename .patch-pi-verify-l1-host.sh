#!/usr/bin/env bash
set -euo pipefail

f="tools/payloads/usr-local-share/sysclone-pi.mk"
[ -f "$f" ] || { echo "ERROR: $f not found"; exit 1; }

tmp="$(mktemp)"
cp -a "$f" "$tmp"

# 1) Ensure the env preview uses sudo
#    Replace: sed -n '1,20p' /etc/sysclone/firstboot.env
#    With   : sudo sed -n '1,20p' /etc/sysclone/firstboot.env
if grep -q "sed -n '1,20p' /etc/sysclone/firstboot.env" "$tmp"; then
  sed -i "s|sed -n '1,20p' /etc/sysclone/firstboot.env|sudo sed -n '1,20p' /etc/sysclone/firstboot.env|g" "$tmp"
fi

# 2) Replace fragile wants/ symlink ls with a service-enabled check
#    Replace line containing:
#      /etc/systemd/system/multi-user.target.wants/sysclone-first-boot.service
#    With two lines:
#      echo "(expected after success: disabled)"
#      systemctl is-enabled sysclone-first-boot.service || true
awk '
  {
    if ($0 ~ /multi-user\.target\.wants\/sysclone-first-boot\.service/) {
      print "echo \"(expected after success: disabled)\""
      print "systemctl is-enabled sysclone-first-boot.service || true"
      next
    }
    print
  }
' "$tmp" > "${tmp}.new"

mv "${tmp}.new" "$f"
rm -f "$tmp"

echo "[ok] updated $f"
