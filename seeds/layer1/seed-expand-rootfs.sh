#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT_MNT:-/mnt/sysclone-root}"

log(){ echo "[seed:l1] $*"; }

[[ -d "$ROOT/etc" ]] || { echo "[seed:l1] ERR: $ROOT not mounted"; exit 2; }

install -D -m 0755 tools/payloads/usr-local-sbin/sysclone-expand-rootfs.sh \
  "$ROOT/usr/local/sbin/sysclone-expand-rootfs.sh"

install -D -m 0644 tools/payloads/etc-systemd-system-sysclone-expand-rootfs.service \
  "$ROOT/etc/systemd/system/sysclone-expand-rootfs.service"

ln -sfn ../sysclone-expand-rootfs.service \
  "$ROOT/etc/systemd/system/multi-user.target.wants/sysclone-expand-rootfs.service"

echo "[seed:l1] staged expand-rootfs unit + script (enabled)"
