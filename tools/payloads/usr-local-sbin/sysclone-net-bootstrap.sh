#!/usr/bin/env bash
set -Eeuo pipefail

log(){ printf '[net-strap] %s\n' "$*"; }

# 0) Clock sane (harmless if already configured)
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-ntp true || true
fi

# 1) Keyrings (only if not initialized)
if ! pacman-key --list-keys >/dev/null 2>&1; then
  log "init keyring"
  rm -rf /etc/pacman.d/gnupg
  pacman-key --init
  pacman-key --populate archlinuxarm manjaro manjaro-arm
fi

# 2) Mirrors (Manjaro ARM): choose ONE mode; fasttrack is fine
if command -v pacman-mirrors >/dev/null 2>&1; then
  pacman-mirrors --fasttrack || true
fi

# 3) Refresh DBs (safe to repeat)
pacman -Syy

# 4) Minimal trust deps (safe if already present)
pacman -S --needed --noconfirm ca-certificates ca-certificates-mozilla

# 5) Write done-stamp to avoid reruns
install -d -m 0755 /var/lib/sysclone
: > /var/lib/sysclone/net-bootstrap.done
log "done"
