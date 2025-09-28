#!/usr/bin/env bash
set -euo pipefail
mf=Makefile
[[ -f "$mf" ]] || { echo "Makefile not found"; exit 2; }

awk '
  BEGIN{ in=0 }
  # Match the target header (keep it), then emit a fresh recipe and skip the old one
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
  # While in the old recipe, skip lines that look like part of it:
  in==1 {
    # skip continued recipe lines (start with whitespace) until a non-indented line (next target / stanza)
    if ($0 ~ /^[ \t]/) next
    in=0
  }
  { print }
' "$mf" > "$mf.__new__"

mv "$mf.__new__" "$mf"
echo "[ok] replaced seed-pi-devtools recipe with sudo installs"
