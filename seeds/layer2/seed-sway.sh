#!/usr/bin/env bash
set -euo pipefail
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

echo "[seed] layer2: sway configs/wrappers"

install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
  "$ROOT_MNT/usr/local/bin/start-sway"

install -D -m 0644 tools/payloads/etc-skel-config-sway \
  "$ROOT_MNT/etc/skel/.config/sway/config"

install -d -m 0755 "$ROOT_MNT/home/username/.config/sway"
install -m 0644 tools/payloads/etc-skel-config-sway \
  "$ROOT_MNT/home/username/.config/sway/config"

# Best-effort ownership (harmless on host without chroot)
if command -v chroot >/dev/null 2>&1; then
  chroot "$ROOT_MNT" chown -R username:username "/home/username/.config" || true
fi

echo "[seed] layer2: sway payloads seeded (packages will install on boot)"
