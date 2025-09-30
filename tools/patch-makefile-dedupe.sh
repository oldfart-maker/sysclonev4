#!/usr/bin/env bash
set -Eeuo pipefail
mf="Makefile"
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

awk '
BEGIN{
  seen_export=0
  seen_root=0
  seen_boot=0
  in_dup_block=0
  inserted_flash_expand=0
}
{
  line=$0

  # Start of the duplicate block we want to drop:
  if (line ~ /^DEVICE[[:space:]]*\?=/ && in_dup_block==0) {
    in_dup_block=1
    next
  }

  # Inside duplicate block: skip until the dashed terminator comment
  if (in_dup_block==1) {
    if (line ~ /^# --------------------------------------------[[:space:]]*$/) {
      in_dup_block=0
    }
    next
  }

  # Dedup export line: keep only first occurrence of exactly this form
  if (line ~ /^export[[:space:]]+ROOT_MNT[[:space:]]+BOOT_MNT[[:space:]]+DEVICE[[:space:]]*$/) {
    if (seen_export==1) next
    seen_export=1
    print line
    next
  }

  # Dedup ROOT_MNT/BOOT_MNT ?= definitions: keep only first per var
  if (line ~ /^ROOT_MNT[[:space:]]*\?=/) {
    if (seen_root==1) next
    seen_root=1
    print line
    next
  }
  if (line ~ /^BOOT_MNT[[:space:]]*\?=/) {
    if (seen_boot==1) next
    seen_boot=1
    print line
    next
  }

  # Remember whether flash-all+expand exists already
  if (line ~ /^flash-all\+expand:/) {
    inserted_flash_expand=1
  }

  # Print current line
  print line

  # After the flash-all target, insert flash-all+expand if missing
  if (line ~ /^flash-all:[[:space:]]/) {
    if (inserted_flash_expand==0) {
      print ""
      print "# Convenience: unpack + write + offline expand (re-uses existing targets/vars)"
      print "flash-all+expand: img-unpack sd-write img-expand-rootfs-offline  ## unpack, write, expand (offline)"
      print ""
      inserted_flash_expand=1
    }
  }
}
' "$mf" > "$mf.tmp"

mv -f "$mf.tmp" "$mf"
echo "[dedupe] wrote $mf (backup at $bak)"
