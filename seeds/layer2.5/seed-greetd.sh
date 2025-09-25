#!/usr/bin/env bash
# Seed greetd config + wrapper + sway session into mounted ROOT
# This does NOT chroot; packages get installed on boot by the layer2.5 service.
set -euo pipefail

log(){ echo "[seed:layer2.5] $*"; }

: "${ROOT_MNT:?ROOT_MNT not set}"
ROOT="$ROOT_MNT"

log "greetd (config + launcher + sessions) -> $ROOT"

# 1) Config points greetd at our wrapper
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"

# 2) Wrapper prefers tuigreet; falls back to start-sway
install -D -m 0755 tools/payloads/usr-local-bin/greetd-launcher \
  "$ROOT/usr/local/bin/greetd-launcher"

# 3) Sway session so tuigreet lists it
install -D -m 0644 tools/payloads/usr-share-wayland-sessions/sway.desktop \
  "$ROOT/usr/share/wayland-sessions/sway.desktop"

# 4) Ensure start-sway exists (layer2 usually installs it)
if [ ! -x "$ROOT/usr/local/bin/start-sway" ]; then
  log "start-sway missing; installing minimal wrapper"
  install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
    "$ROOT/usr/local/bin/start-sway"
fi

log "greetd payloads staged (config, launcher, sway.desktop)"
