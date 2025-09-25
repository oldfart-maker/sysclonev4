#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[layer2-install] $*"; }

# --- brief wait for sane clock (TLS) ---
log "waiting briefly for time sync…"
deadline=$((SECONDS+90))
while :; do
  synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
  now=$(date +%s)
  [ "$synced" = "yes" ] && break
  [ "$now" -ge 1704067200 ] && break  # >= 2024-01-01
  sleep 3
  [ $SECONDS -gt $deadline ] && break
done

log "pacman -Syy (refresh db)"
pacman -Syy --noconfirm || true

# Remove packages that cause/trigger the hybris conflict if present (ignore errors)
TO_REMOVE=(ocl-icd libhybris libhybris-28-glvnd libhybris-glvnd libhybris-git)
log "pre-clean: ${TO_REMOVE[*]}"
pacman -R --noconfirm "${TO_REMOVE[@]}" 2>/dev/null || true
pacman -Rn --noconfirm "${TO_REMOVE[@]}" 2>/dev/null || true

# Install providers FIRST to avoid prompts
PROVIDERS=(mesa ffmpeg pipewire-jack ttf-dejavu)
log "install providers first: ${PROVIDERS[*]}"
pacman -S --needed --noconfirm --overwrite='*' "${PROVIDERS[@]}"

# Base Wayland/Sway packages
BASE_PKGS=(
  wayland wlroots
  foot grim slurp kanshi wf-recorder
  xdg-desktop-portal xdg-desktop-portal-wlr
  pipewire wireplumber pipewire-alsa pipewire-pulse
  sway swaybg swayidle swaylock dmenu
)

# Some Manjaro ARM dep chains try to pull 'libhybris' as a provider.
# We *do not* want libhybris on Pi; satisfy it virtually so pacman never prompts.
ASSUME=(--assume-installed libhybris=0)

log "install Wayland/Sway stack (non-interactive; no hybris)"
set -x
pacman -S --needed --noconfirm --overwrite='*' "${ASSUME[@]}" "${BASE_PKGS[@]}"
set +x

# Enable audio/session services for all users (safe to repeat)
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true

install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.layer2-installed
log "done"
