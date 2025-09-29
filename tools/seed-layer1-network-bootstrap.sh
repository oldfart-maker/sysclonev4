#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[layer1] $*"; }
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

install -d -m 0755 \
  "$ROOT_MNT/usr/local/sbin" \
  "$ROOT_MNT/etc/systemd/system" \
  "$ROOT_MNT/var/lib/sysclone"

# --- on-target helper (first boot, runs once) ---
cat > "$ROOT_MNT/usr/local/sbin/sysclone-network-bootstrap.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[net-bootstrap] $*"; }
STAMP=/var/lib/sysclone/.network-bootstrap.done
[ -e "$STAMP" ] && { log "already done"; exit 0; }

# --- helpers ---
wait_for_clock(){
  # Wait for NTPSynchronized or a sane epoch (>= 2024-01-01)
  local deadline=$(( $(date +%s) + 90 ))
  local target_epoch=1704067200
  while [ "$(date -u +%s)" -lt "$target_epoch" ]; do
    synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)"
    [ "$synced" = yes ] && break
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 2
  done
  return 0
}

fallback_ntp(){
  if command -v busybox >/dev/null 2>&1; then
    busybox ntpd -n -q -p pool.ntp.org && return 0 || true
  fi
  return 1
}

fallback_set_http_date(){
  # Use plain HTTP Date (no TLS) to get a rough clock
  local d
  d="$(curl -fsI --max-time 8 http://google.com 2>/dev/null \
       | awk -F': ' '/^Date:/{print $2; exit}')"
  if [ -n "${d:-}" ]; then
    date -u -s "$d" >/dev/null 2>&1 || true
  fi
}

# --- clock / timesyncd ---
log "enabling NTP and trying to sync clock"
timedatectl set-ntp true || true
systemctl restart systemd-timesyncd || true
if ! wait_for_clock; then
  log "clock not synced; trying quick NTP and HTTP-Date fallback"
  fallback_ntp || true
  synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)"
  now="$(date -u +%s 2>/dev/null || echo 0)"
  if [ "$synced" != yes ] && [ "${now:-0}" -lt 1704067200 ]; then
    log "using HTTP Date fallback, then restarting timesyncd"
    fallback_set_http_date || true
    timedatectl set-ntp true || true
    systemctl restart systemd-timesyncd || true
    wait_for_clock || true
  fi
fi

# --- certs / keyrings / mirrors ---
log "ensuring CA certs"
pacman -Sy --noconfirm --needed ca-certificates ca-certificates-mozilla || true

log "ensuring pacman keyrings"
pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring archlinuxarm-keyring manjaro-arm-keyring || true

if command -v pacman-mirrors >/dev/null 2>&1; then
  log "refreshing Manjaro mirrors (best-effort)"
  pacman-mirrors --fasttrack 5 --geoip || true
fi

log "refreshing databases"
pacman -Syy || true

# stamp and exit
install -d -m 0755 /var/lib/sysclone
touch "$STAMP"
log "done"
EOS
chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-network-bootstrap.sh"

# --- systemd unit (runs once, before your first-boot unit) ---
cat > "$ROOT_MNT/etc/systemd/system/sysclone-network-bootstrap.service" <<'EOS'
[Unit]
Description=SysClone: Bootstrap network time, certs, and keyrings (first boot)
Wants=network-online.target systemd-timesyncd.service
After=network-online.target systemd-timesyncd.service
Before=sysclone-first-boot.service
ConditionPathExists=!/var/lib/sysclone/.network-bootstrap.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-network-bootstrap.sh

[Install]
WantedBy=multi-user.target
EOS

ln -sf ../sysclone-network-bootstrap.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-network-bootstrap.service" 2>/dev/null || true

log "staged sysclone-network-bootstrap.service + script"
