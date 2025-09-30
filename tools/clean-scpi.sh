#!/usr/bin/env bash
set -euo pipefail

SCPI="tools/payloads/usr-local-bin/scpi"
[ -f "$SCPI" ] || { echo "missing $SCPI"; exit 1; }

bak="${SCPI}.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$SCPI" "$bak"

perl -0777 -pe '
  # 1) Strip all existing helper definitions we manage
  s/^\s*fallback_ntp\(\)\s*\{.*?^\}\s*\n//gms;
  s/^\s*fallback_set_http_date\(\)\s*\{.*?^\}\s*\n//gms;
  s/^\s*wait_for_clock\(\)\s*\{.*?^\}\s*\n//gms;
  s/^\s*ensure_net_bootstrap\(\)\s*\{.*?^\}\s*\n//gms;

  # 2) Normalize bootstrap_make() to a single canonical implementation
  s/^\s*bootstrap_make\(\)\s*\{.*?^\}\s*\n/
bootstrap_make() {
  echo "[scpi] '"'make'"' not found, bootstrapping…"
  if ! command -v pacman >/dev/null 2>&1; then
    echo "[scpi] pacman not found; please install '"'make'"' manually"; exit 1
  fi
  ensure_net_bootstrap
  sudo pacman -Syyu --noconfirm --needed make
}
\n/gms;

  # 3) Insert ONE shared helper block after the first non-comment line (ideally after set -euo pipefail)
  # Find a good anchor: the first occurrence of "set -e" or "set -euo pipefail"
  if ($_ !~ /# --- sysclone net\/certs bootstrap helpers/){
    $_ =~ s/^(.*?set -e[^\n]*\n)/$1# --- sysclone net\/certs bootstrap helpers (shared) ---\nwait_for_clock() {\n  local deadline=$(( \$(date +%s) + 90 ))\n  local target_epoch=1704067200 # 2024-01-01 UTC\n  while [ \"\$(date -u +%s)\" -lt \"\$target_epoch\" ]; do\n    local synced\n    synced=\"\$(timedatectl show -p NTPSynchronized --value 2>\/dev\/null || echo no)\"\n    [ \"\$synced\" = yes ] && break\n    [ \"\$(date +%s)\" -ge \"\$deadline\" ] && return 1\n    sleep 2\n  done\n  return 0\n}\n\nfallback_ntp() {\n  if command -v busybox >\/dev\/null 2>&1; then\n    busybox ntpd -n -q -p pool.ntp.org && return 0 || true\n  fi\n  return 1\n}\n\nfallback_set_http_date() {\n  # Use plain HTTP (no TLS) to read Date header and set a coarse clock\n  local d\n  d=\"\$(curl -fsI --max-time 8 http:\/\/google.com 2>\/dev\/null | awk -F\": \" '\''/^Date:/{print \$2; exit}'\'')\"\n  if [ -n \"\${d:-}\" ]; then\n    date -u -s \"\$d\" >\/dev\/null 2>&1 || true\n  fi\n}\n\nensure_net_bootstrap() {\n  echo \"[scpi] ensuring sane clock and package trust (NTP, CA, keyrings, mirrors)\"\n  sudo timedatectl set-ntp true || true\n  sudo systemctl restart systemd-timesyncd || true\n  if ! wait_for_clock; then\n    echo \"[scpi] WARN: clock not yet synced; trying quick NTP + HTTP-Date fallback\"\n    fallback_ntp || true\n    local synced now\n    synced=\"\$(timedatectl show -p NTPSynchronized --value 2>\/dev\/null || echo no)\"\n    now=\"\$(date -u +%s 2>\/dev\/null || echo 0)\"\n    if [ \"\$synced\" != yes ] && [ \"\${now:-0}\" -lt 1704067200 ]; then\n      fallback_set_http_date || true\n      sudo timedatectl set-ntp true || true\n      sudo systemctl restart systemd-timesyncd || true\n      wait_for_clock || true\n    fi\n  fi\n  # Certs first (TLS to mirrors)\n  sudo pacman -Sy --noconfirm --needed ca-certificates ca-certificates-mozilla || true\n  # Keyrings next\n  sudo pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring archlinuxarm-keyring manjaro-arm-keyring || true\n  # Manjaro mirror refresh if available (best-effort)\n  if command -v pacman-mirrors >\/dev\/null 2>&1; then\n    sudo pacman-mirrors --fasttrack 5 --geoip || true\n  fi\n  # Fresh DBs\n  sudo pacman -Syy || true\n}\n\n/si;
  }

' -i "$SCPI"

chmod 0755 "$SCPI"
echo "[clean-scpi] updated $SCPI (backup at $bak)"
