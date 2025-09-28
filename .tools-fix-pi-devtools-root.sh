#!/usr/bin/env bash
set -euo pipefail
mf=Makefile
[[ -f "$mf" ]] || { echo "Makefile not found"; exit 2; }

# add sudo to the two install lines inside seed-pi-devtools
awk '
  BEGIN { in=0 }
  /^seed-pi-devtools:/ { in=1 }
  in && /install -D -m 0644 tools\/payloads\/usr-local-share\/sysclone-pi.mk/ {
    sub(/^(\s*)install /, "\\1sudo install ")
  }
  in && /install -D -m 0755 tools\/payloads\/usr-local-bin\/scpi/ {
    sub(/^(\s*)install /, "\\1sudo install ")
  }
  { print }
  in && /^\s*\$\(MAKE\) ensure-unmounted/ { in=0 }
' "$mf" > "$mf.__new__" && mv "$mf.__new__" "$mf"

echo "[ok] added sudo to pi-devtools installs"
