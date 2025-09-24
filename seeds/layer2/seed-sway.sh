#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR%/seeds/*}"

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
  echo "[seed:layer2] Could not determine ROOT_MNT. Ensure the root partition is mounted (Makefile handles this) or export ROOT_MNT/ROOT_LABEL." >&2
  exit 1
fi

echo "[seed] layer2: sway configs/wrappers"

install -D -m 0755 "$REPO_ROOT/tools/payloads/usr-local-bin/start-sway" \
  "$ROOT_MNT/usr/local/bin/start-sway"

install -D -m 0644 "$REPO_ROOT/tools/payloads/etc-skel-config-sway" \
  "$ROOT_MNT/etc/skel/.config/sway/config"

install -d -m 0755 "$ROOT_MNT/home/username/.config/sway"
install -m 0644 "$REPO_ROOT/tools/payloads/etc-skel-config-sway" \
  "$ROOT_MNT/home/username/.config/sway/config"

# Best-effort ownership (harmless on host without chroot)
if command -v chroot >/dev/null 2>&1; then
  chroot "$ROOT_MNT" chown -R username:username "/home/username/.config" || true
fi

echo "[seed] layer2: sway payloads seeded (packages will install on boot)"
