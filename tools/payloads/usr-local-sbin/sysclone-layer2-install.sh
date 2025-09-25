#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[layer2-install] $*"; }

# --- brief wait for sane clock (TLS); never infinite ---
log "waiting briefly for time sync…"
deadline=$((SECONDS+120))
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

# --- ruthlessly remove troublemakers if present (ignore failures) ---
TO_REMOVE=(ocl-icd libhybris libhybris-28-glvnd libhybris-glvnd libhybris-git)
log "pre-clean (force) any: ${TO_REMOVE[*]}"
pacman -Rdd --noconfirm "${TO_REMOVE[@]}" 2>/dev/null || true
pacman -Rnsc --noconfirm "${TO_REMOVE[@]}" 2>/dev/null || true

# --- install providers FIRST so pacman never prompts later ---
# include libglvnd explicitly so GL deps are satisfied w/o hybris
PROVIDERS=(mesa libglvnd ffmpeg pipewire-jack ttf-dejavu)
log "install providers first: ${PROVIDERS[*]}"
pacman -S --needed --noconfirm --overwrite='*' "${PROVIDERS[@]}"

# --- base Wayland/Sway packages ---
BASE_PKGS=(
  wayland wlroots
  foot grim slurp kanshi wf-recorder
  xdg-desktop-portal xdg-desktop-portal-wlr
  pipewire wireplumber pipewire-alsa pipewire-pulse
  sway swaybg swayidle swaylock dmenu
)

# Some Manjaro ARM chains try to pull a hybris provider; we reject them all.
ASSUME=(--assume-installed libhybris=0 --assume-installed libhybris-28-glvnd=0 --assume-installed libhybris-glvnd=0 --assume-installed libhybris-git=0)

log "install Wayland/Sway stack (non-interactive; no hybris)"
set -x
pacman -S --needed --noconfirm --overwrite='*' "${ASSUME[@]}" "${BASE_PKGS[@]}"
set +x

# enable audio/session services for all users (safe if already enabled)
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true

install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.layer2-installed
log "done"
