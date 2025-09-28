#!/usr/bin/env bash
set -euo pipefail
INS=tools/payloads/usr-local-sbin/sysclone-layer2-install.sh
[[ -f "$INS" ]] || { echo "missing $INS"; exit 2; }

# 1) Add helpers once: wait_clock + fallback_mirrorlist
grep -q 'l2_wait_clock()' "$INS" || cat >> "$INS" <<'EOF'

# --- sysclone:l2 clock + mirrors hardening ------------------------------------
l2_wait_clock() {
  # Wait up to 300s for either NTP= yes or a reasonable year (>= 2024)
  local deadline=$((SECONDS+300))
  while (( SECONDS < deadline )); do
    local ntp; ntp="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)"
    local yr;  yr="$(date -u +%Y 2>/dev/null || echo 1970)"
    if [[ "$ntp" = "yes" ]] || (( yr >= 2024 )); then
      echo "[layer2-install] clock ready (ntp=$ntp year=$yr)"
      return 0
    fi
    sleep 2
  done
  echo "[layer2-install] WARN: clock not confirmed after wait; proceeding cautiously"
  return 0
}

l2_write_fallback_mirrorlist() {
  cat > /etc/pacman.d/mirrorlist <<'ML'
##
## Fallback mirrorlist (sysclone L2)
##

Server = https://mirror.fcix.net/manjaro/$branch/$repo/$arch
Server = https://ftp.halifax.rwth-aachen.de/manjaro/$branch/$repo/$arch
Server = https://ftp.tsukuba.wide.ad.jp/Linux/manjaro/$branch/$repo/$arch
ML
  echo "[layer2-install] wrote fallback /etc/pacman.d/mirrorlist"
}
# ------------------------------------------------------------------------------
EOF

# 2) Call l2_wait_clock before any pacman-mirrors/pacman work
# Insert just before the "05 refresh mirrors + db" step header if present
if grep -n '\[layer2-install\] 05 refresh mirrors' "$INS" >/dev/null; then
  awk '
    { print }
    /\[layer2-install\] 05 refresh mirrors/ && !done {
      print "l2_wait_clock"
      done=1
    }
  ' "$INS" > "$INS.__new__" && mv "$INS.__new__" "$INS"
fi

# 3) Wrap pacman-mirrors with a fallback if it errors (keep your existing output)
# Replace the line that runs pacman-mirrors -f if present; otherwise append a guarded block
if grep -q 'pacman-mirrors' "$INS"; then
  sed -i 's/pacman-mirrors -f.*/if pacman-mirrors -f --silent; then echo "[layer2-install] pacman-mirrors ok"; else echo "[layer2-install] pacman-mirrors failed; using fallback"; l2_write_fallback_mirrorlist; fi/' "$INS"
else
  # Append a conservative update block
  cat >> "$INS" <<'EOF'
# Refresh mirrors; if it fails (TLS/clock), write a static fallback list
if pacman-mirrors -f --silent; then
  echo "[layer2-install] pacman-mirrors ok"
else
  echo "[layer2-install] pacman-mirrors failed; using fallback"
  l2_write_fallback_mirrorlist
fi
EOF
fi

echo "[ok] patched $INS (clock wait + mirrorlist fallback)"
