#!/usr/bin/env bash
set -euo pipefail

ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

install -d -m 0755 "$ROOT_MNT/usr/local/sbin" \
                    "$ROOT_MNT/etc/systemd/system" \
                    "$ROOT_MNT/var/lib/sysclone"

# On-target bootstrap script
cat > "$ROOT_MNT/usr/local/sbin/sysclone-net-bootstrap.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail

STAMP=/var/lib/sysclone/.net-bootstrap.done
[ -f "$STAMP" ] && exit 0

log(){ echo "[sysclone-net-bootstrap] $*"; }

# 0) Coarse clock via HTTP Date (no TLS)
if command -v curl >/dev/null 2>&1; then
  d="$(curl -fsI --max-time 8 http://google.com 2>/dev/null | awk -F': ' '/^Date:/{print $2; exit}')"
  [ -n "${d:-}" ] && date -u -s "$d" >/dev/null 2>&1 || true
fi

# 1) Certs + keyrings first (so TLS + pacman trust are OK)
log "bootstrap CA certs"
pacman -Sy --noconfirm --needed ca-certificates ca-certificates-mozilla || true

log "bootstrap keyrings"
pacman -Sy --noconfirm --needed archlinux-keyring manjaro-keyring archlinuxarm-keyring manjaro-arm-keyring || true

# 2) Switch to chrony for reliable time
log "install chrony + disable systemd-timesyncd"
pacman -S --noconfirm --needed chrony || true
systemctl disable --now systemd-timesyncd || true

# chrony config (simple, robust pools)
install -d -m 0755 /etc/chrony
cat > /etc/chrony/chrony.conf <<'CFG'
pool time.cloudflare.com iburst
pool time.google.com iburst
pool 0.pool.ntp.org iburst
pool 1.pool.ntp.org iburst
makestep 1.0 3
rtcsync
driftfile /var/lib/chrony/drift
CFG

systemctl enable --now chronyd || true

# Give chrony a moment to poll, then proceed
sleep 6

# 3) Manjaro mirror refresh (best-effort), then hard DB refresh
log "refreshing Manjaro mirrors (fasttrack)"
if command -v pacman-mirrors >/dev/null 2>&1; then
  pacman-mirrors --fasttrack 5 || true
fi

log "pacman -Syy to refresh DBs"
pacman -Syy || true

# 4) Stamp and done
touch "$STAMP"
log "done"
EOS
chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-net-bootstrap.sh"

# Systemd unit (oneshot, runs before multi-user, only if no stamp)
cat > "$ROOT_MNT/etc/systemd/system/sysclone-net-bootstrap.service" <<'UNIT'
[Unit]
Description=SysClone: Network/clock/certs/keyrings bootstrap
Wants=network-online.target
After=network-online.target
Before=multi-user.target
ConditionPathExists=!/var/lib/sysclone/.net-bootstrap.done

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-net-bootstrap.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

ln -sf ../sysclone-net-bootstrap.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-net-bootstrap.service" 2>/dev/null || true

echo "[seed-net-bootstrap] staged chrony-based net/clock bootstrap"
