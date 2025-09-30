#!/usr/bin/env bash
set -Eeuo pipefail

SCPI="tools/payloads/usr-local-bin/scpi"
[ -f "$SCPI" ] || { echo "missing $SCPI"; exit 2; }

bak="${SCPI}.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$SCPI" "$bak"

# Find bootstrap_make() start/end by brace counting to avoid fragile regex.
start_line=
end_line=
brace=0
in=0
lineno=0

while IFS= read -r line; do
  lineno=$((lineno+1))
  if [[ $in -eq 0 && $line == "bootstrap_make() {" ]]; then
    start_line=$lineno
    in=1
    brace=1
    continue
  fi
  if [[ $in -eq 1 ]]; then
    # count braces on the line
    opens=$(grep -o '{' <<<"$line" | wc -l | tr -d ' ')
    closes=$(grep -o '}' <<<"$line" | wc -l | tr -d ' ')
    brace=$(( brace + opens - closes ))
    if [[ $brace -eq 0 ]]; then
      end_line=$lineno
      break
    fi
  fi
done < "$SCPI"

if [[ -z $start_line || -z $end_line ]]; then
  echo "Could not locate bootstrap_make() in $SCPI"
  exit 3
fi

head -n $((start_line-1)) "$SCPI" > "$SCPI.new"

# Insert fallback helpers if not already present (cheap check for function name)
if ! grep -q '^fallback_ntp()' "$SCPI"; then
  cat >> "$SCPI.new" <<'EOS'

# Fallbacks when NTP is slow/unavailable
fallback_ntp() {
  if command -v busybox >/dev/null 2>&1; then
    busybox ntpd -n -q -p pool.ntp.org && return 0
  fi
  return 1
}

fallback_set_http_date() {
  # Use a plain HTTP Date header (no TLS) to roughly set clock
  local d
  d=$(curl -fsI --max-time 8 http://google.com 2>/dev/null | awk -F": " '/^Date:/{print $2; exit}')
  if [ -n "$d" ]; then
    # Example: Sun, 28 Sep 2025 23:14:15 GMT
    sudo date -u -s "$d" >/dev/null 2>&1 || true
  fi
}
EOS
fi

# Write the new bootstrap_make() body
cat >> "$SCPI.new" <<'EOS'
bootstrap_make() {
  echo "[scpi] 'make' not found, bootstrapping…"
  if ! command -v pacman >/dev/null 2>&1; then
    echo "[scpi] pacman not found; please install 'make' manually"; exit 1
  fi

  # Ensure NTP is on and wait for a sane clock (TLS mirrors need correct time)
  sudo timedatectl set-ntp true || true
  sudo systemctl restart systemd-timesyncd || true
  if ! wait_for_clock; then
    echo "[scpi] WARN: clock not yet synced; trying quick NTP and HTTP-Date fallback"
    # try a quick NTP one-shot via busybox (if available)
    fallback_ntp || true
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
    now=$(date -u +%s 2>/dev/null || echo 0)
    if [ "$synced" != yes ] && [ "${now:-0}" -lt 1704067200 ]; then
      echo "[scpi] clock still off; setting from HTTP Date, then re-enabling NTP"
      fallback_set_http_date || true
      sudo timedatectl set-ntp true || true
      sudo systemctl restart systemd-timesyncd || true
      wait_for_clock || true
    fi
  fi

  # Make sure CA roots + keyrings present before any TLS mirror pulls
  sudo pacman -Sy --noconfirm --needed ca-certificates ca-certificates-mozilla || true
  sudo pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring archlinuxarm-keyring manjaro-arm-keyring || true

  # On Manjaro ARM, refreshing mirrors can help; best-effort only
  if command -v pacman-mirrors >/dev/null 2>&1; then
    sudo pacman-mirrors --fasttrack 5 --geoip || true
  fi

  # Update and install
  sudo pacman -Syyu --noconfirm --needed make
}
EOS

# Append the tail (everything after original function)
tail -n +"$((end_line+1))" "$SCPI" >> "$SCPI.new"

mv "$SCPI.new" "$SCPI"
chmod 0755 "$SCPI"
echo "[patch-scpi-bootstrap] updated $SCPI (backup at $bak)"
