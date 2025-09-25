#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[seed:layer2.5] $*"; }
: "${ROOT_MNT:?ROOT_MNT not set}"
ROOT="$ROOT_MNT"

log "greetd (config + launcher + sway.desktop + tty drop-in) -> $ROOT"

# Config + wrapper
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"
install -D -m 0755 tools/payloads/usr-local-bin/greetd-launcher \
  "$ROOT/usr/local/bin/greetd-launcher"

# Ensure start-sway exists
install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
  "$ROOT/usr/local/bin/start-sway"

# Optional: session file (only if present in repo)
if [ -f "tools/payloads/usr-share-wayland-sessions/sway.desktop" ]; then
  install -D -m 0644 tools/payloads/usr-share-wayland-sessions/sway.desktop \
    "$ROOT/usr/share/wayland-sessions/sway.desktop"
fi

# Drop-in to pin greetd to tty1
install -D -m 0644 tools/payloads/etc-systemd-system-greetd.service.d-tty.conf \
  "$ROOT/etc/systemd/system/greetd.service.d/tty.conf"

log "greetd payloads staged"
