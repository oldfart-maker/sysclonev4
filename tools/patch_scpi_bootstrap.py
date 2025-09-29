#!/usr/bin/env python3
import re, sys
from pathlib import Path

scpi_path = Path("tools/payloads/usr-local-bin/scpi")
if not scpi_path.exists():
    print("ERROR: missing tools/payloads/usr-local-bin/scpi", file=sys.stderr)
    sys.exit(2)

text = scpi_path.read_text()

def find_function(text, name):
    m = re.search(rf'^[ \t]*{re.escape(name)}\s*\(\)\s*\{{', text, re.M)
    if not m:
        return None
    start = m.start()
    i = m.end() - 1  # at '{'
    depth = 0
    while i < len(text):
        c = text[i]
        if c == '{':
            depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0:
                return (start, i + 1)
        i += 1
    return None

def ensure_helpers(text):
    need = []
    if not re.search(r'^\s*fallback_ntp\(\)\s*\{', text, re.M):
        need.append(r'''
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
    sudo date -u -s "$d" >/dev/null 2>&1 || true
  fi
}
'''.strip("\n"))
    if not need:
        return text, False
    sheb = re.search(r'^#!.*\n', text)
    insert_at = sheb.end() if sheb else 0
    new = text[:insert_at] + "\n" + "\n".join(need) + "\n" + text[insert_at:]
    return new, True

fn_range = find_function(text, "bootstrap_make")
if not fn_range:
    print("ERROR: could not locate bootstrap_make()", file=sys.stderr)
    sys.exit(3)

text, helpers_added = ensure_helpers(text)
if helpers_added:
    fn_range = find_function(text, "bootstrap_make")
    if not fn_range:
        print("ERROR: after inserting helpers, bootstrap_make() not found", file=sys.stderr)
        sys.exit(4)

start, end = fn_range
header_match = re.match(r'^[ \t]*bootstrap_make\(\)\s*\{', text[start:end], re.S | re.M)
header = header_match.group(0)
indent = re.match(r'^([ \t]*)', header).group(1)

body = f'''{header}
  echo "[scpi] 'make' not found, bootstrapping…"
  if ! command -v pacman >/dev/null 2>&1; then
    echo "[scpi] pacman not found; please install 'make' manually"; exit 1
  fi

  # Ensure NTP is on and wait for a sane clock (TLS mirrors need correct time)
  sudo timedatectl set-ntp true || true
  sudo systemctl restart systemd-timesyncd || true
  if ! wait_for_clock; then
    echo "[scpi] WARN: clock not yet synced; trying quick NTP and HTTP-Date fallback"
    fallback_ntp || true
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
    now=$(date -u +%s 2>/dev/null || echo 0)
    if [ "$synced" != yes ] && [ "${{now:-0}}" -lt 1704067200 ]; then
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
{indent}}}
'''

new_text = text[:start] + body + text[end:]
scpi_path.write_text(new_text)
print("[patch_scpi_bootstrap] scpi updated successfully")
