#!/usr/bin/env bash

wait_pacman() {
  local t=0;
  while [[ -e /var/lib/pacman/db.lck ]] || pgrep -x pacman >/dev/null; do
    ((t++)); if (( t>300 )); then echo "[layer2-install] timeout waiting for pacman lock"; return 1; fi
    sleep 1;
  done
}

set -euo pipefail

STEP=0
log(){ printf '[layer2-install] %02d %s\n' "$STEP" "$*"; }
next(){ STEP=$((STEP+1)); }

# pacman wrapper: quiet but not silent; always allow overwrite
PAC="pacman --noconfirm --noprogressbar --overwrite=*"

# tee logs to file for post-mortem
LOGF=/var/log/sysclone-layer2.log
exec > >(tee -a "$LOGF") 2>&1

# ---------- time sync ----------
next; log "version 2025-09-25.2"
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

# ---------- keyring init (Arch, Manjaro, Manjaro ARM, ArchLinuxARM) ----------
next; log "init/repair pacman keyring"
mkdir -p /etc/pacman.d/gnupg && chmod 700 /etc/pacman.d/gnupg || true
# Install keyring pkgs locally (ok if DB stale; we refresh mirrors next)
$PAC -Sy archlinux-keyring manjaro-keyring manjaro-arm-keyring archlinuxarm-keyring || true
# Initialize + populate – no network required
pacman-key --init || true
pacman-key --populate archlinux manjaro manjaro-arm archlinuxarm || true

# ---------- mirrors + db ----------
next; log "refresh mirrors + db"
if command -v pacman-mirrors >/dev/null 2>&1; then
wait_pacman || exit 1
  pacman-mirrors --fasttrack 5 --api --protocol https || true
fi
$PAC -Syy || true

# ---------- pre-clean conflicts ----------
next; log "pre-clean (force) ocl-icd + libhybris* if present"
$PAC -Rdd  ocl-icd libhybris libhybris-28-glvnd libhybris-glvnd libhybris-git 2>/dev/null || true
$PAC -Rnsc ocl-icd libhybris libhybris-28-glvnd libhybris-glvnd libhybris-git 2>/dev/null || true

# ---------- providers first to avoid prompts ----------
next; log "providers first: mesa libglvnd ffmpeg pipewire-jack ttf-dejavu"
$PAC -S --needed mesa libglvnd ffmpeg pipewire-jack ttf-dejavu

# ---------- Wayland/Sway stack (block hybris via assume-installed) ----------
next; log "Wayland/Sway stack (assume no hybris)"
ASSUME=(--assume-installed libhybris=0 --assume-installed libhybris-28-glvnd=0 \
        --assume-installed libhybris-glvnd=0 --assume-installed libhybris-git=0)
$PAC -S --needed "${ASSUME[@]}" \
  wayland wlroots \
  foot grim slurp kanshi wf-recorder \
  xdg-desktop-portal xdg-desktop-portal-wlr \
  pipewire wireplumber pipewire-alsa pipewire-pulse \
  sway swaybg swayidle swaylock dmenu

# ---------- enable audio session units ----------
next; log "enable audio session units (global)"
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true

# ---------- stamp success ----------
next; log "stamp success"
install -d -m 0755 /var/lib/sysclone
printf 'ok\n' > /var/lib/sysclone/.layer2-installed

next; log "done"

# --- sysclone:l2 clock + mirrors hardening ------------------------------------
l2_wait_clock() {
  # Wait up to 300s for either NTP= yes or a reasonable year (>= 2024)
  local deadline=$((SECONDS+300))
  while (( SECONDS < deadline )); do
    local ntp; ntp="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)"
    local yr;  yr="$(date -u +%Y 2>/dev/null || echo 1970)"
    if [[ "$ntp" = "yes" ]] || (( yr >= 2024 )); then
      echo "[layer2-install] clock ready (ntp=$ntp year=$yr)"
      return 0
    fi
    sleep 2
  done
  echo "[layer2-install] WARN: clock not confirmed after wait; proceeding cautiously"
  return 0
}

l2_write_fallback_mirrorlist() {
  cat > /etc/pacman.d/mirrorlist <<'ML'
##
## Fallback mirrorlist (sysclone L2)
##

Server = https://mirror.fcix.net/manjaro/$branch/$repo/$arch
Server = https://ftp.halifax.rwth-aachen.de/manjaro/$branch/$repo/$arch
Server = https://ftp.tsukuba.wide.ad.jp/Linux/manjaro/$branch/$repo/$arch
ML
  echo "[layer2-install] wrote fallback /etc/pacman.d/mirrorlist"
}
# ------------------------------------------------------------------------------
