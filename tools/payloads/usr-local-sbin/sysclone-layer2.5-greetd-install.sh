#!/usr/bin/env bash
set -euo pipefail
echo "[layer2.5-install] installing greetd + tuigreet"
pacman -Sy --noconfirm
pacman -S --needed --noconfirm greetd tuigreet
systemctl enable greetd.service
install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.layer2.5-greetd-installed
echo "[layer2.5-install] done"
