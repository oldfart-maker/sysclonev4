#!/usr/bin/env bash
# Seed greetd config + wrapper + sway session into mounted ROOT, and stage an on-boot installer
set -euo pipefail
log(){ echo "[seed:layer2.5] $*"; }

: "${ROOT_MNT:?ROOT_MNT not set}"
ROOT="$ROOT_MNT"

log "greetd (config + launcher + sessions) -> $ROOT"

# 1) Config and launcher
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"
install -D -m 0755 tools/payloads/usr-local-bin/greetd-launcher \
  "$ROOT/usr/local/bin/greetd-launcher"

# 2) Sway session entry (for greeters that use sessions menu)
install -D -m 0644 tools/payloads/usr-share-wayland-sessions/sway.desktop \
  "$ROOT/usr/share/wayland-sessions/sway.desktop" 2>/dev/null || true

# 3) Ensure start-sway exists
install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
  "$ROOT/usr/local/bin/start-sway"

# 4) On-boot installer: install+enable greetd/seatd, add greeter to groups
install -D -m 0755 /dev/stdin "$ROOT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh" <<'EOSH'
#!/usr/bin/env bash
set -euo pipefail
echo "[layer2.5] installing greetd/seatd + configuring groups"

PAC=${PAC:-/usr/bin/pacman}

# Install greetd, agreety and seatd; try tuigreet if available in repos
$PAC -Sy --noconfirm --needed greetd seatd || true
$PAC -Sy --noconfirm --needed greetd-tuigreet || true
$PAC -Sy --noconfirm --needed agreety || true

# Enable seatd and greetd
systemctl enable --now seatd.service || true
systemctl enable greetd.service || true

# Make sure greeter can talk to seatd and input/video
id -u greeter >/dev/null 2>&1 || useradd -r -s /bin/bash -U greeter || true
usermod -aG video,input greeter || true
getent group seat >/dev/null 2>&1 && usermod -aG seat greeter || true

# Optional: ensure sway.desktop exists (if not already)
install -D -m 0644 /usr/share/wayland-sessions/sway.desktop /usr/share/wayland-sessions/sway.desktop 2>/dev/null || true

# Done; don’t re-run automatically
touch /var/lib/sysclone/.layer2.5-greetd-installed
EOSH

# 5) Systemd unit to run the on-boot installer once
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

# Enable the oneshot
ln -sf ../sysclone-layer2.5-greetd-install.service \
  "$ROOT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd-install.service"

log "greetd payloads staged (config, launcher, start-sway, on-boot installer)"
