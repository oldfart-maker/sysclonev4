#!/usr/bin/env bash
set -euo pipefail

ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"
ARCH_CHROOT="arch-chroot"

$ARCH_CHROOT "$ROOT_MNT" bash -lc \
  'pacman -S --noconfirm sway swaybg swayidle swaylock dmenu'

# Start wrapper (for login via TTY: log in as "username" then run "start-sway")
install -D -m 0755 tools/payloads/usr-local-bin/start-sway \
  "$ROOT_MNT/usr/local/bin/start-sway"

# Minimal sway config into /etc/skel for new users and /home/username for your default user
install -D -m 0644 tools/payloads/etc-skel-config-sway \
  "$ROOT_MNT/etc/skel/.config/sway/config"
install -d -m 0755 "$ROOT_MNT/home/username/.config/sway"
install -m 0644 tools/payloads/etc-skel-config-sway \
  "$ROOT_MNT/home/username/.config/sway/config"
chroot "$ROOT_MNT" chown -R username:username "/home/username/.config"
