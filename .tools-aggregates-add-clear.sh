#!/usr/bin/env bash
set -euo pipefail
mf=Makefile
[[ -f "$mf" ]] || { echo "Makefile not found"; exit 2; }

awk -v RS='\n' -v ORS='\n' '
  function insert_clear(line, stamp) {
    if (!inserted && line ~ /^\t@set -euo pipefail; \\[[:space:]]*$/) {
      print line
      print "\t  $(MAKE) " stamp "; \\"
      inserted = 1
      next
    }
  }
  BEGIN { in1=in2=in25=0; inserted=0 }
  {
    if ($0 ~ /^seed-layer1-all:/) { in1=1; in2=0; in25=0; inserted=0 }
    else if ($0 ~ /^seed-layer2-all:/) { in1=0; in2=1; in25=0; inserted=0 }
    else if ($0 ~ /^seed-layer2\.5-all:/) { in1=0; in2=0; in25=1; inserted=0 }
    else if ($0 ~ /^[^ \t].*:/ && $0 !~ /^seed-layer(1|2|2\.5)-all:/) { in1=in2=in25=0; inserted=0 }

    if (in1) { insert_clear($0, "clear-layer1-stamps") }
    else if (in2) { insert_clear($0, "clear-layer2-stamps") }
    else if (in25) { insert_clear($0, "clear-layer2.5-stamps") }

    print
  }
' "$mf" > "$mf.__new__"

mv "$mf.__new__" "$mf"
echo "[ok] aggregates now clear stamps at start of each recipe"
