#!/usr/bin/env bash
# Seed greetd config + wrapper + sway session into mounted ROOT
set -euo pipefail
log(){ echo "[seed:layer2.5] $*"; }

: "${ROOT_MNT:?ROOT_MNT not set}"
ROOT="$ROOT_MNT"

log "greetd (config + launcher + sessions) -> $ROOT"

# config
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"

# wrapper (kept even if not default)
install -D -m 0755 tools/payloads/usr-local-bin/greetd-launcher \
  "$ROOT/usr/local/bin/greetd-launcher"

# start-sway (ensure present)
install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
  "$ROOT/usr/local/bin/start-sway"

# sway.desktop
install -D -m 0644 tools/payloads/usr-share-wayland-sessions/sway.desktop \
  "$ROOT/usr/share/wayland-sessions/sway.desktop"

log "greetd payloads staged (config, launcher, sway.desktop, start-sway)"
