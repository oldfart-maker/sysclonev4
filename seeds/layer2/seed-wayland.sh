#!/usr/bin/env bash
set -euo pipefail

# Auto-sudo when not root
SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  SUDO="sudo"
fi

# Resolve repo root (run from anywhere)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/seeds/*}"

# Find ROOT_MNT: prefer env, else derive from ROOT_LABEL's mounted device
ROOT_MNT="${ROOT_MNT:-}"
if [[ -z "${ROOT_MNT}" ]]; then
  if [[ -n "${ROOT_LABEL:-}" ]]; then
    dev="$(blkid -L "${ROOT_LABEL}" 2>/dev/null || true)"
    if [[ -n "$dev" ]]; then
      ROOT_MNT="$(findmnt -n -o TARGET --source "$dev" 2>/dev/null || true)"
    fi
  fi
fi
if [[ -z "${ROOT_MNT}" || ! -d "${ROOT_MNT}/etc" ]]; then
  echo "[seed:layer2] Could not determine ROOT_MNT. Ensure the root partition is mounted or export ROOT_MNT/ROOT_LABEL." >&2
  exit 1
fi

if command -v arch-chroot >/dev/null 2>&1; then
  ARCH_CHROOT="arch-chroot"
  echo "[seed] layer2: using arch-chroot path"
  $SUDO $ARCH_CHROOT "$ROOT_MNT" bash -lc \
    'pacman -Syu --noconfirm wayland wlroots foot grim slurp kanshi wf-recorder \
                           xdg-desktop-portal xdg-desktop-portal-wlr \
                           pipewire wireplumber pipewire-alsa pipewire-pulse'
else
  echo "[seed] layer2: arch-chroot not found; staging on-boot installer"
  $SUDO install -D -m 0755 "$REPO_ROOT/tools/payloads/usr-local-sbin/sysclone-layer2-install.sh" \
    "$ROOT_MNT/usr/local/sbin/sysclone-layer2-install.sh"
  $SUDO install -D -m 0644 "$REPO_ROOT/tools/payloads/etc/systemd/system/sysclone-layer2-install.service" \
    "$ROOT_MNT/etc/systemd/system/sysclone-layer2-install.service"
  $SUDO install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
  $SUDO ln -sf ../sysclone-layer2-install.service \
    "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer2-install.service"
fi

# Always install helper
$SUDO install -D -m 0755 "$REPO_ROOT/tools/payloads/usr-local-sbin/wayland-sanity.sh" \
  "$ROOT_MNT/usr/local/sbin/wayland-sanity.sh"

echo "[seed] layer2: wayland core seeded (or staged for on-boot)"
