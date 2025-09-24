#!/usr/bin/env bash
set -euo pipefail

ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"  # set by your Makefile seed plumbing
ARCH_CHROOT="arch-chroot"                   # manjaro also ships arch-chroot

# Base wayland/wlroots + basic portals & pipewire stack (safe even if Layer 3 adds more later)
$ARCH_CHROOT "$ROOT_MNT" bash -lc \
  'pacman -Syu --noconfirm wayland wlroots foot grim slurp kanshi wf-recorder \
                         xdg-desktop-portal xdg-desktop-portal-wlr \
                         pipewire wireplumber pipewire-alsa pipewire-pulse'

# Wayland sanity script (TTY-friendly)
install -D -m 0755 tools/payloads/usr-local-sbin/wayland-sanity.sh \
  "$ROOT_MNT/usr/local/sbin/wayland-sanity.sh"
