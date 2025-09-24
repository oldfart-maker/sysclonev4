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
  echo "[seed:layer2.5] Could not determine ROOT_MNT. Ensure the root partition is mounted (Makefile handles this) or export ROOT_MNT/ROOT_LABEL." >&2
  exit 1
fi

echo "[seed] layer2.5: staging greetd on-boot installer"
install -D -m 0755 "$REPO_ROOT/tools/payloads/usr-local-sbin/sysclone-layer2.5-greetd-install.sh" \
  "$ROOT_MNT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh"
install -D -m 0644 "$REPO_ROOT/tools/payloads/etc/systemd/system/sysclone-layer2.5-greetd-install.service" \
  "$ROOT_MNT/etc/systemd/system/sysclone-layer2.5-greetd-install.service"
install -D -m 0644 "$REPO_ROOT/tools/payloads/etc-greetd-config.toml" \
  "$ROOT_MNT/etc/greetd/config.toml"

install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
ln -sf ../sysclone-layer2.5-greetd-install.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd-install.service"

echo "[seed] layer2.5: greetd installer staged (will run on first boot)"
