#!/usr/bin/env bash
# Seed greetd config + wrapper + sway session into mounted ROOT, and stage an on-boot installer
set -euo pipefail
log(){ echo "[seed:layer2.5] $*"; }

: "${ROOT_MNT:?ROOT_MNT not set}"
ROOT="$ROOT_MNT"

log "greetd (config + launcher + sessions) -> $ROOT"

# Config & launcher
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"
install -D -m 0755 tools/payloads/usr-local-bin/greetd-launcher \
  "$ROOT/usr/local/bin/greetd-launcher"

# Session entry (best-effort if repo doesn’t ship one)
install -D -m 0644 tools/payloads/usr-share-wayland-sessions/sway.desktop \
  "$ROOT/usr/share/wayland-sessions/sway.desktop" 2>/dev/null || true

# start-sway helper
install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
  "$ROOT/usr/local/bin/start-sway"

# greetd VT drop-in inside target
install -D -m 0644 tools/payloads/etc-systemd-system-greetd.service.d-tty.conf \
  "$ROOT/etc/systemd/system/greetd.service.d/tty.conf"

# On-boot installer: greetd/seatd, greeter groups, optional tuigreet
install -D -m 0755 /dev/stdin "$ROOT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh" <<'EOSH'
#!/usr/bin/env bash
set -euo pipefail
echo "[layer2.5] installing greetd/seatd + configuring groups"

PAC=${PAC:-/usr/bin/pacman}
$PAC -Sy --noconfirm --needed seatd greetd || true
$PAC -Sy --noconfirm --needed greetd-tuigreet || true
$PAC -Sy --noconfirm --needed agreety || true

systemctl enable --now seatd.service || true
systemctl enable greetd.service || true

id -u greeter >/dev/null 2>&1 || useradd -r -s /bin/bash -U greeter || true
usermod -aG video,input greeter || true
getent group seat >/dev/null 2>&1 && usermod -aG seat greeter || true

# sway.desktop (best-effort)
install -D -m 0644 /usr/share/wayland-sessions/sway.desktop /usr/share/wayland-sessions/sway.desktop 2>/dev/null || true

touch /var/lib/sysclone/.layer2.5-greetd-installed
EOSH

# One-shot unit
install -D -m 0644 /dev/stdin "$ROOT/etc/systemd/system/sysclone-layer2.5-greetd-install.service" <<'EOUNIT'
[Unit]
Description=SysClone Layer 2.5 On-Boot Installer (greetd + seatd + launcher)
ConditionPathExists=!/var/lib/sysclone/.layer2.5-greetd-installed
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-layer2.5-greetd-install.sh

[Install]
WantedBy=multi-user.target
EOUNIT

ln -sf ../sysclone-layer2.5-greetd-install.service \
  "$ROOT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd-install.service"

log "greetd payloads staged (config, launcher, start-sway, tty drop-in, on-boot installer)"
