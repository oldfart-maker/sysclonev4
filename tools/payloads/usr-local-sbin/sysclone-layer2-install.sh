#!/usr/bin/env bash
set -euo pipefail

STEP=0
log(){ printf '[layer2-install] %02d %s\n' "$STEP" "$*"; }
next(){ STEP=$((STEP+1)); }

# Make pacman quieter but still reliable
PAC="pacman --noconfirm --noprogressbar --overwrite='*'"

# Log also to file for post-mortem
LOGF=/var/log/sysclone-layer2.log
exec > >(tee -a "$LOGF") 2>&1

next; log "version 2025-09-25.1"
next; log "enable NTP + restart timesyncd"
timedatectl set-ntp true || true
systemctl restart systemd-timesyncd.service || true

next; log "wait for sane clock (<=300s)"
deadline=$((SECONDS+300))
while :; do
  synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
  now=$(date +%s)
  [ "$synced" = "yes" ] || [ "$now" -ge 1704067200 ] && break
  sleep 3
  [ $SECONDS -gt $deadline ] && break
done
log "clock ok (synced=$synced now=$now)"

next; log "init/repair pacman keyring"
mkdir -p /etc/pacman.d/gnupg && chmod 700 /etc/pacman.d/gnupg || true
$PAC -Sy archlinux-keyring manjaro-keyring manjaro-arm-keyring || true
pacman-key --init || true
pacman-key --populate archlinux manjaro manjaro-arm || true

next; log "refresh mirrors + db"
if command -v pacman-mirrors >/dev/null 2>&1; then
  pacman-mirrors --fasttrack 5 --api --protocol https || true
fi
$PAC -Syy || true

next; log "pre-clean (force) ocl-icd + libhybris* if present"
$PAC -Rdd ocl-icd libhybris libhybris-28-glvnd libhybris-glvnd libhybris-git 2>/dev/null || true
$PAC -Rnsc ocl-icd libhybris libhybris-28-glvnd libhybris-glvnd libhybris-git 2>/dev/null || true

next; log "providers first: mesa libglvnd ffmpeg pipewire-jack ttf-dejavu"
$PAC -S --needed mesa libglvnd ffmpeg pipewire-jack ttf-dejavu

next; log "Wayland/Sway stack (assume no hybris)"
ASSUME=(--assume-installed libhybris=0 --assume-installed libhybris-28-glvnd=0 --assume-installed libhybris-glvnd=0 --assume-installed libhybris-git=0)
$PAC -S --needed "${ASSUME[@]}" \
  wayland wlroots \
  foot grim slurp kanshi wf-recorder \
  xdg-desktop-portal xdg-desktop-portal-wlr \
  pipewire wireplumber pipewire-alsa pipewire-pulse \
  sway swaybg swayidle swaylock dmenu

next; log "enable audio session units (global)"
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true

next; log "stamp success"
install -d -m 0755 /var/lib/sysclone
printf 'ok\n' > /var/lib/sysclone/.layer2-installed

next; log "done"
