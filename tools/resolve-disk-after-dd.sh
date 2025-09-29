#!/usr/bin/env bash
set -Eeuo pipefail
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"
TIMEOUT="${TIMEOUT:-60}"; SLEEP_INT="${SLEEP_INT:-0.5}"
have(){ command -v "$1" >/dev/null 2>&1; }
die(){ printf '[resolver] ERROR: %s\n' "$*" >&2; exit 1; }
dev_by_label(){ local l="$1" p=""; if have blkid; then p="$(blkid -L "$l" 2>/dev/null || true)"; [[ -n "$p" ]] && readlink -f -- "$p" && return 0; fi
  p="$(lsblk -rpo NAME,LABEL 2>/dev/null | awk -v L="$l" '$2==L{print $1; exit}')"; [[ -n "$p" ]] && readlink -f -- "$p" && return 0; return 1; }
parent_disk(){ local part="$1" p; p="$(lsblk -nrpo PKNAME "$part" 2>/dev/null | head -n1)"; [[ -z "$p" ]] && p="$(lsblk -nrpo NAME "$part" | sed -E 's/p?[0-9]+$//')"; readlink -f -- "${p:-$part}"; }
main(){ have udevadm && udevadm settle || true; local t=0 part=""
  while (( $(printf '%.0f' "$t") < TIMEOUT )); do
    if part="$(dev_by_label "$ROOT_LABEL")"; then parent_disk "$part"; return 0; fi
    if part="$(dev_by_label "$BOOT_LABEL")"; then parent_disk "$part"; return 0; fi
    sleep "$SLEEP_INT"; t=$(awk -v a="$t" -v b="$SLEEP_INT" 'BEGIN{print a+b}')
  done; die "Timed out waiting for labels ($ROOT_LABEL / $BOOT_LABEL)"; }
main "$@"
