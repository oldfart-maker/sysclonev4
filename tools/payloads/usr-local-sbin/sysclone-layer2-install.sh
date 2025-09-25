#!/usr/bin/env bash
set -euo pipefail

log(){ echo "[layer2-install] $*"; }

# --- robust clock sync: enable NTP, restart timesyncd, wait up to 5 minutes ---
sync_clock() {
  log "ensuring NTP is enabled + timesyncd running"
  timedatectl set-ntp true || true
  systemctl restart systemd-timesyncd.service || true

  log "waiting for time sync (up to 300s)…"
  local deadline=$((SECONDS+300))
  while :; do
    local synced now
    synced=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo no)
    now=$(date +%s)
    # treat >= 2024-01-01 as good enough if NTPSynchronized lags on first boot
    if [ "$synced" = "yes" ] || [ "$now" -ge 1704067200 ]; then
      log "time looks sane (synced=$synced now=$now)"
      break
    fi
    sleep 3
    [ $SECONDS -gt $deadline ] && { log "timed wait expired; continuing anyway"; break; }
  done
}

# --- initialize/repair pacman keyring (Manjaro ARM friendly) ---
init_keyring() {
  log "initializing pacman keyring (mkdir/chown/chmod if needed)"
  mkdir -p /etc/pacman.d/gnupg
  chown -R root:root /etc/pacman.d/gnupg || true
  chmod 700 /etc/pacman.d/gnupg || true

  # Pre-install keyring packages (ignore failure if db not yet current)
  pacman -Sy --noconfirm archlinux-keyring manjaro-keyring manjaro-arm-keyring || true

  # Initialize + populate (idempotent)
  pacman-key --init || true
  pacman-key --populate archlinux manjaro manjaro-arm || true
}

# --- Manjaro mirror refresh (fast) to avoid dead/slow mirrors ---
refresh_mirrors() {
  if command -v pacman-mirrors >/dev/null 2>&1; then
    log "refreshing mirrors (fasttrack)"
    pacman-mirrors --fasttrack 5 --api --protocol https || true
    pacman -Syy --noconfirm || true
  else
    log "pacman-mirrors not found; skipping"
    pacman -Syy --noconfirm || true
  fi
}

# --- MAIN ---
sync_clock
init_keyring
refresh_mirrors

# Remove troublemakers (ignore failure if not installed)
TO_REMOVE=(ocl-icd libhybris libhybris-28-glvnd libhybris-glvnd libhybris-git)
log "pre-clean (force) any: ${TO_REMOVE[*]}"
pacman -Rdd --noconfirm "${TO_REMOVE[@]}" 2>/dev/null || true
pacman -Rnsc --noconfirm "${TO_REMOVE[@]}" 2>/dev/null || true

# Providers FIRST so pacman never prompts; include libglvnd explicitly
PROVIDERS=(mesa libglvnd ffmpeg pipewire-jack ttf-dejavu)
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

# Reject all hybris variants via assume-installed (no prompts, no conflicts)
ASSUME=(--assume-installed libhybris=0 --assume-installed libhybris-28-glvnd=0 --assume-installed libhybris-glvnd=0 --assume-installed libhybris-git=0)

log "install Wayland/Sway stack (non-interactive; no hybris)"
set -x
pacman -S --needed --noconfirm --overwrite='*' "${ASSUME[@]}" "${BASE_PKGS[@]}"
set +x

# Enable audio/session services for all users (safe to repeat)
systemctl --global enable pipewire.service pipewire-pulse.service wireplumber.service || true

install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.layer2-installed
log "done"
