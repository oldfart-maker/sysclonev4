#!/usr/bin/env bash
set -euo pipefail

# Overwrite the staged payload files in-repo. Simple here-docs, idempotent.
mkdir -p tools/payloads/usr-local-sbin tools/payloads/etc-systemd-system

# --- payload script ---
cat > tools/payloads/usr-local-sbin/sysclone-net-bootstrap.sh <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
STAMP=/var/lib/sysclone/.net-bootstrap.done
mkdir -p "$(dirname "$STAMP")"

log(){ echo "[sysclone-net-bootstrap] $*"; }

wait_for_clock() {
  local deadline=$(( $(date +%s) + 90 ))
  local target=1704067200 # 2024-01-01 UTC
  while :; do
    local now=$(date -u +%s 2>/dev/null || echo 0)
    [ "$now" -ge "$target" ] && return 0
    local synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
    [ "$synced" = yes ] && return 0
    [ "$(date +%s)" -ge "$deadline" ] && return 1
    sleep 2
  done
}

http_date_bump() {
  # Plain HTTP date (no TLS) to jump the clock if it’s wildly wrong
  local d
  d="$(curl -fsI --max-time 8 http://google.com 2>/dev/null | sed -n 's/^Date: //p' | head -n1)"
  if [ -n "${d:-}" ]; then
    date -u -s "$d" >/dev/null 2>&1 || true
  fi
}

log "enable NTP (timesyncd) and try to sync clock"
timedatectl set-ntp true || true
systemctl restart systemd-timesyncd || true
if ! wait_for_clock; then
  log "clock not synced yet; doing HTTP Date bump and retry"
  http_date_bump || true
  timedatectl set-ntp true || true
  systemctl restart systemd-timesyncd || true
  wait_for_clock || true
fi

log "bootstrap CA certs (TLS to mirrors)"
pacman -Sy --noconfirm --needed ca-certificates ca-certificates-mozilla || true

log "ensure pacman keyring is initialized and writable"
if [ ! -d /etc/pacman.d/gnupg ] || [ ! -w /etc/pacman.d/gnupg ]; then
  rm -rf /etc/pacman.d/gnupg
  pacman-key --init
  pacman-key --populate archlinux manjaro archlinuxarm manjaro-arm
fi
chown -R root:root /etc/pacman.d/gnupg || true
chmod 700 /etc/pacman.d/gnupg 2>/dev/null || true

log "refresh DBs"
pacman -Syy || true

log "install chrony and switch from systemd-timesyncd"
if ! command -v chronyd >/dev/null 2>&1; then
  pacman -S --noconfirm --needed chrony || true
fi
systemctl disable --now systemd-timesyncd 2>/dev/null || true
systemctl enable --now chronyd 2>/dev/null || true

log "refresh Manjaro mirrors (best effort)"
if command -v pacman-mirrors >/dev/null 2>&1; then
  # Avoid --geoip (not always supported); pick 5 fastest
  pacman-mirrors -f 5 || true
fi

log "final DB refresh"
pacman -Syy || true

touch "$STAMP"
log "done"
EOS
chmod 0755 tools/payloads/usr-local-sbin/sysclone-net-bootstrap.sh

# --- unit file ---
cat > tools/payloads/etc-systemd-system/sysclone-net-bootstrap.service <<'EOS'
[Unit]
Description=SysClone: Network/clock/certs/keyrings bootstrap
Wants=network-online.target
After=systemd-timesyncd.service network-pre.target
Before=network-online.target multi-user.target
ConditionPathExists=!/var/lib/sysclone/.net-bootstrap.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-net-bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOS

echo "[update-net-bootstrap] payloads refreshed in repo"
