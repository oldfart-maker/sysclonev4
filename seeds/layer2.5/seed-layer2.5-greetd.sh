#!/usr/bin/env bash
set -euo pipefail

ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"
ARCH_CHROOT="arch-chroot"

$ARCH_CHROOT "$ROOT_MNT" bash -lc 'pacman -S --noconfirm greetd tuigreet'

# Conservative config: no --cmd, no remember-user. Lets users choose session manually.
install -D -m 0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT_MNT/etc/greetd/config.toml"

# Enable greetd (takes over a VT; safe to leave disabled until you’re ready)
chroot "$ROOT_MNT" systemctl enable greetd.service
