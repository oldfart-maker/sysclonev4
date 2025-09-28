#!/usr/bin/env bash
set -euo pipefail
mf=Makefile
[[ -f "$mf" ]] || { echo "Makefile not found"; exit 2; }

awk '
  BEGIN{ in=0 }
  # Enter the recipe when we see the target header:
  /^seed-pi-devtools:[[:space:]]/ { print; in=1; next }
  # While in the recipe (tab-indented lines), add sudo to install lines:
  in==1 && substr($0,1,1) == "\t" {
    line=$0
    if (line ~ /\t.*\binstall -D -m 0644[[:space:]]+tools\/payloads\/usr-local-share\/sysclone-pi.mk/) {
      sub(/\binstall -D /, "sudo install -D ", line)
    }
    if (line ~ /\t.*\binstall -D -m 0755[[:space:]]+tools\/payloads\/usr-local-bin\/scpi/) {
      sub(/\binstall -D /, "sudo install -D ", line)
    }
    print line
    next
  }
  # Exit the recipe when we hit a non-tab line (next target or blank/non-tab):
  in==1 && substr($0,1,1) != "\t" { in=0 }
  { print }
' "$mf" > "$mf.__new__" && mv "$mf.__new__" "$mf"

echo "[ok] ensured sudo on install lines inside seed-pi-devtools recipe"
