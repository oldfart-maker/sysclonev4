#!/usr/bin/env bash
set -euo pipefail
echo "[layer2.5] installing greetd/seatd + configuring groups (with NTP+mirrors self-heal)"

PAC=${PAC:-/usr/bin/pacman}

# 0) Ensure time is sane to avoid TLS “certificate not yet valid”
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-ntp true || true
  systemctl enable --now systemd-timesyncd.service 2>/dev/null || true
fi

# 1) Mirrors: prefer timezone discovery (replacement for deprecated --geoip)
if command -v pacman-mirrors >/dev/null 2>&1; then
  pacman-mirrors --timezone || true
fi

# 2) Refresh package DBs
"$PAC" -Syy --noconfirm || true

# 3) Install what we need. agreety may not exist on Manjaro; ignore if missing.
"$PAC" -S --noconfirm --needed seatd greetd || true
"$PAC" -S --noconfirm --needed greetd-tuigreet || true
"$PAC" -S --noconfirm --needed agreety || true

# 4) Enable seatd (Wayland seat provider)
systemctl enable --now seatd.service || true

# 5) Ensure greeter user is in needed groups
id -u greeter >/dev/null 2>&1 || useradd -M -s /bin/bash greeter || true
usermod -aG video,input greeter || true
getent group seat >/dev/null 2>&1 && usermod -aG seat greeter || true

# 6) Mask getty on tty2 and let greetd own that VT
systemctl mask getty@tty2.service || true

# 7) All set
echo "[layer2.5] greetd/seatd configured"
