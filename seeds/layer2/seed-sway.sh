#!/usr/bin/env bash
set -euo pipefail

SUDO=""
if [ "${EUID:-$(id -u)}" -ne 0 ]; then SUDO="sudo"; fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/seeds/*}"

# Resolve mounted root (Makefile mounts it; we just discover it)
ROOT_MNT="${ROOT_MNT:-}"
if [[ -z "${ROOT_MNT}" ]]; then
  if [[ -n "${ROOT_LABEL:-}" ]]; then
    dev="$(blkid -L "${ROOT_LABEL}" 2>/dev/null || true)"
    [[ -n "$dev" ]] && ROOT_MNT="$(findmnt -n -o TARGET --source "$dev" 2>/dev/null || true)"
  fi
fi
if [[ -z "${ROOT_MNT}" || ! -d "${ROOT_MNT}/etc" ]]; then
  echo "[seed:layer2] Could not determine ROOT_MNT. Ensure the root partition is mounted or export ROOT_MNT/ROOT_LABEL." >&2
  exit 1
fi

echo "[seed] layer2: sway configs/wrappers"

# start-sway and minimal config
$SUDO install -D -m 0755 "$REPO_ROOT/tools/payloads/usr-local-bin/start-sway" \
  "$ROOT_MNT/usr/local/bin/start-sway"
$SUDO install -D -m 0644 "$REPO_ROOT/tools/payloads/etc-skel-config-sway" \
  "$ROOT_MNT/etc/skel/.config/sway/config"

# seed default user's config (ownership fixed on target via one-shot)
$SUDO install -d -m 0755 "$ROOT_MNT/home/username/.config/sway"
$SUDO install -m 0644 "$REPO_ROOT/tools/payloads/etc-skel-config-sway" \
  "$ROOT_MNT/home/username/.config/sway/config"

# Stage a tiny on-boot ownership fix (runs once on the Pi)
$SUDO install -D -m 0755 "$REPO_ROOT/tools/payloads/usr-local-sbin/sysclone-fix-ownership.sh" \
  "$ROOT_MNT/usr/local/sbin/sysclone-fix-ownership.sh"
$SUDO install -D -m 0644 "$REPO_ROOT/tools/payloads/etc/systemd/system/sysclone-fix-ownership.service" \
  "$ROOT_MNT/etc/systemd/system/sysclone-fix-ownership.service"
$SUDO install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
$SUDO ln -sf ../sysclone-fix-ownership.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-fix-ownership.service"

echo "[seed] layer2: sway payloads seeded (packages will install on boot; ownership fixed on first boot)"
