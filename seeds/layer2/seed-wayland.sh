#!/usr/bin/env bash
set -euo pipefail
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

if command -v arch-chroot >/dev/null 2>&1; then
  ARCH_CHROOT="arch-chroot"
  echo "[seed] layer2: using arch-chroot path"
  $ARCH_CHROOT "$ROOT_MNT" bash -lc \
    'pacman -Syu --noconfirm wayland wlroots foot grim slurp kanshi wf-recorder \
                           xdg-desktop-portal xdg-desktop-portal-wlr \
                           pipewire wireplumber pipewire-alsa pipewire-pulse'
else
  echo "[seed] layer2: arch-chroot not found; staging on-boot installer"
  install -D -m 0755 tools/payloads/usr-local-sbin/sysclone-layer2-install.sh \
    "$ROOT_MNT/usr/local/sbin/sysclone-layer2-install.sh"
  install -D -m 0644 tools/payloads/etc/systemd/system/sysclone-layer2-install.service \
    "$ROOT_MNT/etc/systemd/system/sysclone-layer2-install.service"
  install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
  ln -sf ../sysclone-layer2-install.service \
    "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer2-install.service"
fi

# Always install helper
install -D -m 0755 tools/payloads/usr-local-sbin/wayland-sanity.sh \
  "$ROOT_MNT/usr/local/sbin/wayland-sanity.sh"

echo "[seed] layer2: wayland core seeded (or staged for on-boot)"
