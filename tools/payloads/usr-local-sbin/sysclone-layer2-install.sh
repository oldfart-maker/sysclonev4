#!/usr/bin/env bash
set -euo pipefail
PKGS=( wayland wlroots foot grim slurp kanshi wf-recorder
       xdg-desktop-portal xdg-desktop-portal-wlr
       pipewire wireplumber pipewire-alsa pipewire-pulse
       sway swaybg swayidle swaylock dmenu )
echo "[layer2-install] pacman -Sy"
pacman -Sy --noconfirm
echo "[layer2-install] installing: ${PKGS[*]}"
pacman -S --needed --noconfirm "${PKGS[@]}"
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true
install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.layer2-installed
echo "[layer2-install] done"
