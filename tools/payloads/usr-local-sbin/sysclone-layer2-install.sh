#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[layer2-install] $*"; }

# --- Short wait for time sync; never infinite ---
log "waiting briefly for time sync…"
deadline=$((SECONDS+90))
while :; do
  synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
  now=$(date +%s)
  # treat >= 2024-01-01 as "sane"
  if [ "$synced" = "yes" ] || [ "$now" -ge 1704067200 ]; then
    break
  fi
  sleep 3
  [ $SECONDS -gt $deadline ] && break
done

# Be explicit: we do *not* want libhybris on the Pi
REMOVE_CONFLICTS=(libhybris libhybris-28-glvnd libhybris-git libhybris-glvnd ocl-icd)

# Update dbs; tolerate mirror hiccups
log "pacman -Syy"
pacman -Syy --noconfirm || true

# Remove known conflicting providers if present (ignore if not installed)
log "removing conflicting providers if present: ${REMOVE_CONFLICTS[*]}"
pacman -R --noconfirm "${REMOVE_CONFLICTS[@]}" 2>/dev/null || true

# Install base + explicit providers; no prompts.
BASE_PKGS=(
  wayland wlroots
  foot grim slurp kanshi wf-recorder
  xdg-desktop-portal xdg-desktop-portal-wlr
  pipewire wireplumber pipewire-alsa pipewire-pulse
  sway swaybg swayidle swaylock dmenu
)
PROVIDERS=( mesa ffmpeg pipewire-jack ttf-dejavu )

log "installing Wayland/Sway stack (non-interactive; pinned providers)"
set -x
pacman -S --needed --noconfirm --overwrite='*' "${BASE_PKGS[@]}" "${PROVIDERS[@]}"
set +x

# Enable audio for all users (safe to repeat)
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true

install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.layer2-installed
log "done"
