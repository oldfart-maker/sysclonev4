#!/usr/bin/env bash
set -euo pipefail

echo "[layer2-install] gating on time sync…"
deadline=$((SECONDS+90))
while :; do
  synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
  now=$(date +%s)
  # treat >= 2024-01-01 as sane if NTPSynchronized lags
  if [ "$synced" = "yes" ] || [ "$now" -ge 1704067200 ]; then
    break
  fi
  sleep 3
  [ $SECONDS -gt $deadline ] && break
done

echo "[layer2-install] pacman -Syu (refresh/upgrade)"
pacman -Syu --noconfirm || true

echo "[layer2-install] installing Wayland/Sway stack (non-interactive, pinned providers)"
BASE_PKGS=(
  wayland wlroots
  foot grim slurp kanshi wf-recorder
  xdg-desktop-portal xdg-desktop-portal-wlr
  pipewire wireplumber pipewire-alsa pipewire-pulse
  sway swaybg swayidle swaylock dmenu
)
# Providers to avoid interactive prompts and libhybris conflicts:
PROVIDERS=( mesa ffmpeg pipewire-jack ttf-dejavu )

pacman -S --needed --noconfirm "${BASE_PKGS[@]}" "${PROVIDERS[@]}" --overwrite='*'

# enable audio pieces for all users (safe if already enabled)
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true

install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.layer2-installed
echo "[layer2-install] done"
