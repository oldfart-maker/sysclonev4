#!/usr/bin/env bash
set -Eeuo pipefail
mf="Makefile"; tgt="${1:-}"; [[ -n "$tgt" ]] || { echo "usage: $0 <target>"; exit 2; }
[[ -f "$mf" ]] || { echo "[dedupe] ERROR: $mf not found"; exit 1; }
tmp="$(mktemp)"
awk -v TGT="^"tgt"[[:space:]]*:" '
  { lines[NR]=$0; if ($0 ~ TGT) idx[++n]=NR; }
  END{
    if (n<=1){ for(i=1;i<=NR;i++) print lines[i]; exit }
    keep=idx[n];
    i=1
    while(i<=NR){
      s=lines[i]
      if (s ~ TGT && i != keep){
        i++
        while(i<=NR && (lines[i] ~ /^[[:space:]]/ || lines[i] ~ /^[[:space:]]*#/ || lines[i]=="")) i++
        continue
      }
      print s; i++
    }
  }
' "$mf" > "$tmp"
cmp -s "$mf" "$tmp" || mv "$tmp" "$mf"
rm -f "$tmp" 2>/dev/null || true
