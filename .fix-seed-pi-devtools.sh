#!/usr/bin/env bash
set -euo pipefail
mf=Makefile
tmp="$mf.__new__"

awk '
  BEGIN{ in=0 }
  # Print the target header and replace its whole recipe with two simple lines.
  /^seed-pi-devtools:[[:space:]]/{
    print $0
    print "\t@set -euo pipefail"
    print "\t@bash tools/seed-pi-devtools.sh"
    print "\t@$(MAKE) ensure-unmounted"
    in=1
    next
  }
  # Skip the old recipe lines (indented) until the next non-indented line.
  in==1 {
    if ($0 ~ /^[ \t]/) next
    in=0
  }
  { print }
' "$mf" > "$tmp" && mv "$tmp" "$mf"
