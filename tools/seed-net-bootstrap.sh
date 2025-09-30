#!/usr/bin/env bash
set -Eeuo pipefail

: "${ROOT_MNT:?Set ROOT_MNT=/mnt/sysclone-root (mounted target rootfs)}"

if [[ ! -d "$ROOT_MNT" ]]; then
  echo "[seed-net] ERROR: ROOT_MNT does not exist: $ROOT_MNT" >&2
  exit 1
fi
if ! mountpoint -q "$ROOT_MNT"; then
  echo "[seed-net] ERROR: ROOT_MNT is not mounted: $ROOT_MNT" >&2
  exit 1
fi

echo "[seed-net] ROOT_MNT=$ROOT_MNT"

# 1) Install payload script (on-target helper)
SRC_PAY=tools/payloads/usr-local-sbin/sysclone-net-bootstrap.sh
DST_PAY="$ROOT_MNT/usr/local/sbin/sysclone-net-bootstrap.sh"

if [[ -f "$SRC_PAY" ]]; then
  sudo install -D -m 0755 "$SRC_PAY" "$DST_PAY"
  echo "[seed-net] installed payload: $DST_PAY"
else
  echo "[seed-net] WARN: payload missing: $SRC_PAY (skip payload install)"
fi

# 2) Install systemd unit (either copy from payloads or synthesize a minimal one)
UNIT_DIR_SRC="tools/payloads/etc-systemd-system"
UNIT_NAME="sysclone-net-bootstrap.service"
UNIT_SRC="$UNIT_DIR_SRC/$UNIT_NAME"
UNIT_DST_DIR="$ROOT_MNT/etc/systemd/system"
UNIT_DST="$UNIT_DST_DIR/$UNIT_NAME"

sudo install -d -m 0755 "$UNIT_DST_DIR"

if [[ -f "$UNIT_SRC" ]]; then
  sudo install -m 0644 "$UNIT_SRC" "$UNIT_DST"
  echo "[seed-net] installed unit: $UNIT_DST"
else
  # Minimal, sane defaults: run once after network is online
  sudo tee "$UNIT_DST" >/dev/null <<'UNIT'
[Unit]
Description=Sysclone Layer1: Network/clock/certs bootstrap
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/sysclone-net-bootstrap.sh
# Avoid rerun if a 'done' flag exists
ConditionPathExists=!/var/lib/sysclone/net-bootstrap.done

[Install]
WantedBy=multi-user.target
UNIT
  sudo chmod 0644 "$UNIT_DST"
  echo "[seed-net] synthesized unit: $UNIT_DST"
fi

# 3) Ensure stamp directory exists on target
sudo install -d -m 0755 "$ROOT_MNT/var/lib/sysclone"

# 4) Enable the unit (on the target rootfs)
# Create symlink: /etc/systemd/system/multi-user.target.wants/<unit> -> ../<unit>
WANTS_DIR="$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
sudo install -d -m 0755 "$WANTS_DIR"
if [[ ! -e "$WANTS_DIR/$UNIT_NAME" ]]; then
  (cd "$WANTS_DIR" && sudo ln -s "../$UNIT_NAME" "$UNIT_NAME")
  echo "[seed-net] enabled unit (wants symlink): $WANTS_DIR/$UNIT_NAME"
else
  echo "[seed-net] unit already enabled"
fi

echo "[seed-net] done"
