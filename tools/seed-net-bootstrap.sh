#!/usr/bin/env bash
set -Eeuo pipefail
: "${ROOT_MNT:?Set ROOT_MNT (mounted target rootfs)}"

PAY_BASENAME=sysclone-net-bootstrap.sh
PAY_SRC="tools/payloads/usr-local-sbin/$PAY_BASENAME"
PAY_DST="/usr/local/sbin/$PAY_BASENAME"

# 1) Payload -> target
sudo install -D -m0755 "$PAY_SRC" "$ROOT_MNT$PAY_DST"

# Optional: convenience symlink so PATH=/usr/local/bin finds it too
sudo install -d -m0755 "$ROOT_MNT/usr/local/bin"
if [[ ! -e "$ROOT_MNT/usr/local/bin/$PAY_BASENAME" ]]; then
  ( cd "$ROOT_MNT/usr/local/bin" && sudo ln -s "../sbin/$PAY_BASENAME" "$PAY_BASENAME" )
fi

# 2) Unit -> target (Condition in [Unit], ExecStart matches PAY_DST)
sudo install -d -m0755 "$ROOT_MNT/etc/systemd/system"
sudo tee "$ROOT_MNT/etc/systemd/system/sysclone-net-bootstrap.service" >/dev/null <<UNIT
[Unit]
Description=Sysclone Layer1: Network/clock/certs bootstrap
Wants=network-online.target
After=network-online.target
ConditionPathExists=!/var/lib/sysclone/net-bootstrap.done

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$PAY_DST

[Install]
WantedBy=multi-user.target
UNIT

# 3) Enable on target (create wants symlink)
sudo install -d -m0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
if [[ ! -e "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-net-bootstrap.service" ]]; then
  ( cd "$ROOT_MNT/etc/systemd/system/multi-user.target.wants" && sudo ln -s ../sysclone-net-bootstrap.service sysclone-net-bootstrap.service )
fi

echo "[seed-net] staged: payload=$PAY_DST and unit=.../sysclone-net-bootstrap.service"
