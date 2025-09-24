#!/usr/bin/env bash
set -euo pipefail
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

echo "[seed] layer2.5: staging greetd on-boot installer"
install -D -m 0755 tools/payloads/usr-local-sbin/sysclone-layer2.5-greetd-install.sh \
  "$ROOT_MNT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh"
install -D -m 0644 tools/payloads/etc/systemd/system/sysclone-layer2.5-greetd-install.service \
  "$ROOT_MNT/etc/systemd/system/sysclone-layer2.5-greetd-install.service"
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT_MNT/etc/greetd/config.toml"

install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
ln -sf ../sysclone-layer2.5-greetd-install.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd-install.service"

echo "[seed] layer2.5: greetd installer staged (will run on first boot)"
