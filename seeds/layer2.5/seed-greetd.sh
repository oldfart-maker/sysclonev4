#!/usr/bin/env bash
# Seed greetd config + wrapper + sway session + on-boot installer into mounted ROOT.
# No chroot; packages install on first boot by our oneshot service.
set -euo pipefail

log(){ echo "[seed:layer2.5] $*"; }

: "${ROOT_MNT:?ROOT_MNT not set}"
ROOT="$ROOT_MNT"

# sanity guard so we never write to a garbage path
if [ ! -d "$ROOT/etc" ]; then
  echo "[seed:layer2.5] ERROR: ROOT_MNT ($ROOT) doesn't look like a mounted root (missing /etc)" >&2
  exit 1
fi

log "greetd (config + launcher + sessions) -> $ROOT"

# Config & launcher
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"
install -D -m 0755 tools/payloads/usr-local-bin/greetd-launcher \
  "$ROOT/usr/local/bin/greetd-launcher"

# Session entry (best-effort if repo doesn’t ship one)
install -D -m 0644 tools/payloads/usr-share-wayland-sessions/sway.desktop \
  "$ROOT/usr/share/wayland-sessions/sway.desktop" 2>/dev/null || true

# start-sway helper (ensure present)
install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
  "$ROOT/usr/local/bin/start-sway"

# greetd VT drop-in inside target
install -D -m 0644 tools/payloads/etc-systemd-system-greetd.service.d-tty.conf \
  "$ROOT/etc/systemd/system/greetd.service.d/tty.conf"

# On-boot installer: greetd/seatd, groups, (optional) tuigreet
install -D -m 0755 /dev/stdin "$ROOT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh" <<'EOSH'
#!/usr/bin/env bash
set -euo pipefail
echo "[layer2.5] installing greetd/seatd + configuring groups"

PAC=${PAC:-/usr/bin/pacman}
# core bits
$PAC -Sy --noconfirm --needed seatd greetd || true
# greeters (both ok to “fail” if not in repo)
$PAC -Sy --noconfirm --needed greetd-tuigreet || true
$PAC -Sy --noconfirm --needed agreety || true

# seatd running
systemctl enable --now seatd.service || true

# groups for greeter
id greeter >/dev/null 2>&1 || useradd -r -M -s /bin/bash greeter || true
usermod -aG video,input greeter || true
getent group seat >/dev/null 2>&1 && usermod -aG seat greeter || true

# sway session file (ensure exists)
install -D -m 0644 /usr/share/wayland-sessions/sway.desktop \
  /usr/share/wayland-sessions/sway.desktop 2>/dev/null || true

# greetd drop-in already staged by seed; just enable greetd
systemctl enable greetd.service || true

# prefer tuigreet if present; otherwise agreety (wrapper handles flags)
if command -v tuigreet >/dev/null 2>&1; then
  sed -i 's#^command = .*#command = "/usr/local/bin/greetd-launcher"#' /etc/greetd/config.toml || true
else
  sed -i 's#^command = .*#command = "/usr/bin/agreety --cmd /usr/local/bin/start-sway"#' /etc/greetd/config.toml || true
fi

# ensure start-sway exists and is executable
install -D -m 0755 /usr/local/bin/start-sway /usr/local/bin/start-sway 2>/dev/null || true
chmod 0755 /usr/local/bin/start-sway || true

echo "[layer2.5] greetd/seatd configured"
EOSH

# oneshot service to run the script on first boot
install -D -m 0644 /dev/stdin "$ROOT/etc/systemd/system/sysclone-layer2.5-greetd-install.service" <<'EOSVC'
[Unit]
Description=SysClone Layer 2.5 On-Boot Installer (greetd + seatd + greeter)
ConditionPathExists=!/var/lib/sysclone/.layer2.5-greetd-installed
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-layer2.5-greetd-install.sh
ExecStartPost=/usr/bin/mkdir -p /var/lib/sysclone
ExecStartPost=/usr/bin/touch /var/lib/sysclone/.layer2.5-greetd-installed
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOSVC

# enable oneshot inside target
ln -sf ../sysclone-layer2.5-greetd-install.service \
  "$ROOT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd-install.service"

log "greetd payloads staged"
