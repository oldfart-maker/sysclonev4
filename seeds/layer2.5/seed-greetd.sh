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
install -D -m 0755 tools/payloads/usr-local-sbin/sysclone-layer2.5-greetd-install.sh \
  "$ROOT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh"

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
