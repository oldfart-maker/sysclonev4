#!/usr/bin/env python3
import re
from pathlib import Path

scpi_path = Path("tools/payloads/usr-local-bin/scpi")
if not scpi_path.exists():
    raise SystemExit("missing tools/payloads/usr-local-bin/scpi")

orig = scpi_path.read_text()

# --- 1) Strip any existing helper definitions we manage ---
def strip_func(src, name):
    # Matches: name() { ... } with balanced braces heuristically (non-greedy to next line starting with })
    pat = re.compile(
        rf"(?m)^\s*{re.escape(name)}\s*\(\)\s*\{{.*?^\}}\s*\n?",
        re.DOTALL,
    )
    return re.sub(pat, "", src)

clean = orig
for fn in ["wait_for_clock", "fallback_ntp", "fallback_set_http_date", "ensure_net_bootstrap"]:
    clean = strip_func(clean, fn)

# --- 2) Normalize bootstrap_make() body ---
bootstrap_pat = re.compile(r"(?m)^\s*bootstrap_make\(\)\s*\{.*?^\}\s*\n?", re.DOTALL)
bootstrap_body = r'''bootstrap_make() {
  echo "[scpi] 'make' not found, bootstrapping…"
  if ! command -v pacman >/dev/null 2>&1; then
    echo "[scpi] pacman not found; please install 'make' manually"; exit 1
  fi
  ensure_net_bootstrap
  sudo pacman -Syyu --noconfirm --needed make
}
'''
clean = re.sub(bootstrap_pat, bootstrap_body, clean)

# --- 3) Insert ONE shared helper block after the first 'set -e' line (if not already present) ---
marker = "# --- sysclone net/certs bootstrap helpers (shared) ---"
if marker not in clean:
    helper_block = r'''# --- sysclone net/certs bootstrap helpers (shared) ---
wait_for_clock() {
  local deadline=$(( $(date +%s) + 90 ))
  local target_epoch=1704067200 # 2024-01-01 UTC
  while [ "$(date -u +%s)" -lt "$target_epoch" ]; do
    local synced
    synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)"
    [ "$synced" = yes ] && break
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 2
  done
  return 0
}

fallback_ntp() {
  if command -v busybox >/dev/null 2>&1; then
    busybox ntpd -n -q -p pool.ntp.org && return 0 || true
  fi
  return 1
}

fallback_set_http_date() {
  # Use plain HTTP (no TLS) to read Date header and set a coarse clock
  local d
  d="$(curl -fsI --max-time 8 http://google.com 2>/dev/null | awk -F": " '/^Date:/{print $2; exit}')"
  if [ -n "${d:-}" ]; then
    date -u -s "$d" >/dev/null 2>&1 || true
  fi
}

ensure_net_bootstrap() {
  echo "[scpi] ensuring sane clock and package trust (NTP, CA, keyrings, mirrors)"
  sudo timedatectl set-ntp true || true
  sudo systemctl restart systemd-timesyncd || true
  if ! wait_for_clock; then
    echo "[scpi] WARN: clock not yet synced; trying quick NTP + HTTP-Date fallback"
    fallback_ntp || true
    local synced now
    synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)"
    now="$(date -u +%s 2>/dev/null || echo 0)"
    if [ "$synced" != yes ] && [ "${now:-0}" -lt 1704067200 ]; then
      fallback_set_http_date || true
      sudo timedatectl set-ntp true || true
      sudo systemctl restart systemd-timesyncd || true
      wait_for_clock || true
    fi
  fi
  # Certs first (TLS to mirrors)
  sudo pacman -Sy --noconfirm --needed ca-certificates ca-certificates-mozilla || true
  # Keyrings next
  sudo pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring archlinuxarm-keyring manjaro-arm-keyring || true
  # Manjaro mirror refresh if available (best-effort)
  if command -v pacman-mirrors >/dev/null 2>&1; then
    sudo pacman-mirrors --fasttrack 5 --geoip || true
  fi
  # Fresh DBs
  sudo pacman -Syy || true
}
'''
    # find anchor after first `set -e` or `set -euo pipefail`
    set_e_pat = re.compile(r"(?m)^\s*set\s+-e[^\n]*\n")
    m = set_e_pat.search(clean)
    if m:
        idx = m.end()
        clean = clean[:idx] + helper_block + "\n" + clean[idx:]
    else:
        # fallback: prepend at top
        clean = helper_block + "\n" + clean

# Write back if changed
if clean != orig:
    backup = scpi_path.with_suffix(".bak")
    scpi_path.with_suffix(".bak").write_text(orig)
    scpi_path.write_text(clean)
    print(f"[clean-scpi] updated {scpi_path} (backup at {backup})")
else:
    print("[clean-scpi] no changes (already normalized)")
