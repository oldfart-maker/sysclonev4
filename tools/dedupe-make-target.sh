#!/usr/bin/env bash
set -Eeuo pipefail
mf="Makefile"
tgt="${1:-}"
if [[ -z "$tgt" ]]; then
  echo "usage: $0 <target-name>"; exit 2
fi
[[ -f "$mf" ]] || { echo "[dedupe] ERROR: $mf not found"; exit 1; }

tmp="$(mktemp)"
awk -v TGT="^"tgt"[[:space:]]*:" '
  # A “target header” is a non-indented line that looks like: name: ...
  function is_target_header(s) {
    if (s ~ /^[[:space:]]/) return 0;
    if (s ~ /:=[^=]*/) return 0;              # var assignment
    if (s ~ /[^:]*::[^=]*$/) return 1;        # double-colon target also OK
    if (s ~ /[^=]+:[^=]*$/) return 1;         # single-colon target
    return 0;
  }
  {
    line[NR]=$0;
    if ($0 ~ TGT) idx[++n]=NR;
  }
  END {
    if (n <= 1) { for(i=1;i<=NR;i++) print line[i]; exit }
    keep = idx[n]; # keep ONLY the last target block

    i=1
    while (i<=NR) {
      s=line[i]
      if (s ~ TGT) {
        if (i != keep) {
          # skip this block until next target header line
          i++
          while (i<=NR && (line[i] ~ /^[[:space:]]/ || line[i]=="" )) i++   # recipe/blank continuation
          # also skip comments immediately attached to recipe (optional)
          while (i<=NR && line[i] ~ /^[[:space:]]*#/) i++
          # now continue printing from here without printing skipped lines
          continue
        }
      }
      print s
      i++
    }
  }
' "$mf" > "$tmp"

# Only update if changed
if cmp -s "$mf" "$tmp"; then
  rm -f "$tmp"
  echo "[dedupe] no changes"
else
  mv "$tmp" "$mf"
  echo "[dedupe] updated $mf (kept last definition of target)"
fi
