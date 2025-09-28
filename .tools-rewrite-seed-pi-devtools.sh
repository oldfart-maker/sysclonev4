#!/usr/bin/env bash
set -euo pipefail
mf=Makefile
[[ -f "$mf" ]] || { echo "Makefile not found"; exit 2; }

awk '
  BEGIN{in=0}
  # When we hit the target header, print it and replace its whole recipe:
  /^seed-pi-devtools:[[:space:]]/ {
    print $0
    print "\t@set -euo pipefail; \\"
    print "\t  sudo install -D -m 0644 tools/payloads/usr-local-share/sysclone-pi.mk \"$(ROOT_MNT)/usr/local/share/sysclone/pi.mk\"; \\"
    print "\t  sudo install -D -m 0755 tools/payloads/usr-local-bin/scpi \"$(ROOT_MNT)/usr/local/bin/scpi\"; \\"
    print "\t  echo \"[pi-devtools] installed: /usr/local/share/sysclone/pi.mk and /usr/local/bin/scpi\"; \\"
    print "\t  $(MAKE) ensure-unmounted"
    in=1
    next
  }
  # Skip old recipe lines (tab-indented) until next non-tab line:
  in==1 && substr($0,1,1) == "\t" { next }
  in==1 { in=0 }
  { print }
' "$mf" > "$mf.__new__" && mv "$mf.__new__" "$mf"

echo "[ok] rewrote seed-pi-devtools recipe with sudo installs"
