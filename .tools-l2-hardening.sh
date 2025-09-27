#!/usr/bin/env bash
set -euo pipefail

edit_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  # 1) Insert a robust clock wait helper after the shebang/set -euo pipefail block (if not present)
  if ! grep -q 'wait_for_sane_clock()' "$f"; then
    awk '
      NR==1 { print; next }
      # inject after the first non-shebang line that sets bash options
      injected==0 && $0 ~ /set -E?euo pipefail/ {
        print
        print ""
        print "# --- clock hardening: wait for a sane time (NTP or HTTPS Date) ---"
        print "wait_for_sane_clock() {"
        print "  # arg1: timeout seconds (default 300)"
        print "  local timeout=\"${1:-300}\""
        print "  local deadline=$(( $(date +%s) + timeout ))"
        print "  # acceptable floor: 2024-01-01 UTC"
        print "  local floor=1704067200"
        print "  systemctl restart systemd-timesyncd 2>/dev/null || true"
        print "  while :; do"
        print "    # 1) happy path: timesyncd says we are synced"
        print "    if [[ \"$(timedatectl show -p NTPSynchronized --value 2>/dev/null)\" == \"yes\" ]]; then"
        print "      # extra safety: ensure now >= floor"
        print "      [[ $(date +%s) -ge $floor ]] && return 0"
        print "    fi"
        print "    # 2) fallback: set from HTTPS Date header if curl is available"
        print "    if command -v curl >/dev/null 2>&1; then"
        print "      hdr=$(curl -I -s --max-time 5 https://www.archlinux.org 2>/dev/null | awk -F\": \" \"/^Date:/ {print \$2; exit}\") || true"
        print "      if [[ -n \"\$hdr\" ]]; then"
        print "        date -s \"\$hdr\" >/dev/null 2>&1 || true"
        print "      fi"
        print "    fi"
        print "    # check time floor again"
        print "    if [[ $(date +%s) -ge $floor ]]; then"
        print "      return 0"
        print "    fi"
        print "    # timeout?"
        print "    if [[ $(date +%s) -ge \$deadline ]]; then"
        print "      return 1"
        print "    fi"
        print "    sleep 3"
        print "  done"
        print "}"
        print ""
        injected=1; next
      }
      { print }
    ' "$f" > "$f.__new__" && mv "$f.__new__" "$f"
  fi

  # 2) Strengthen the existing step "03 wait for sane clock" to actually gate on success
  if grep -q '03 wait for sane clock' "$f"; then
    # After the log line, insert a gate
    awk '
      { print }
      inserted==0 && $0 ~ /03 wait for sane clock/ {
        print "if ! wait_for_sane_clock 300; then"
        print "  echo \"[layer2-install] 03 clock still not sane; aborting to avoid SSL/mirror breakage\" >&2"
        print "  exit 90"
        print "fi"
        inserted=1
      }
    ' "$f" > "$f.__new__" && mv "$f.__new__" "$f"
  fi

  # 3) Ensure keyring is writable & initialized BEFORE any pacman -S / pacman-mirrors
  #    Insert a small block before the first pacman -S or pacman-mirrors
  if ! grep -q 'sysclone-keyring-guard' "$f"; then
    awk '
      BEGIN{done=0}
      {
        if (!done && $0 ~ /(pacman-mirrors|pacman[[:space:]].*-S)/) {
          print "# -- sysclone-keyring-guard: ensure pacman keyring is ready --"
          print "install -d -m 0700 /etc/pacman.d/gnupg"
          print "chown -R root:root /etc/pacman.d/gnupg || true"
          print "chmod 700 /etc/pacman.d/gnupg || true"
          print "pacman-key --init >/dev/null 2>&1 || true"
          print "pacman-key --populate archlinux manjaro manjaro-arm archlinuxarm >/dev/null 2>&1 || true"
          print ""
          done=1
        }
        print
      }
    ' "$f" > "$f.__new__" && mv "$f.__new__" "$f"
  fi

  # 4) Make pacman noninteractive where it already asks "Proceed with installation?"
  sed -i 's/pacman -S /pacman -S --noconfirm /g' "$f"
}

edit_file tools/seed-layer2-wayland.sh
edit_file tools/seed-wayland.sh

chmod +x tools/seed-layer2-wayland.sh tools/seed-wayland.sh 2>/dev/null || true
echo "[l2] hardened seeders (clock wait + keyring guard + noninteractive pacman)."
