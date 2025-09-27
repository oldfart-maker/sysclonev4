#!/usr/bin/env bash
set -euo pipefail
echo "[layer2.5] installing greetd/seatd + configuring groups (robust: NTP/mirrors/lock)"

PAC=${PAC:-/usr/bin/pacman}

# Fail fast (do NOT write the stamp on error)
trap 'echo "[layer2.5] ERROR: on-boot installer failed"; exit 1' ERR

# 0) Ensure time is sane to avoid TLS “certificate not yet valid”
if command -v timedatectl >/dev/null 2>&1; then
  timedatectl set-ntp true || true
  systemctl enable --now systemd-timesyncd.service 2>/dev/null || true
fi

# lock handling
wait_unlock() {
  for _ in $(seq 1 30); do
    [ -e /var/lib/pacman/db.lck ] && sleep 2 || break
  done
  rm -f /var/lib/pacman/db.lck || true
}

# 1) Mirrors (timezone replaces deprecated --geoip)
if command -v pacman-mirrors >/dev/null 2>&1; then
  pacman-mirrors --timezone || true
fi

# 2) Refresh DBs
wait_unlock
"$PAC" -Syy --noconfirm || true

# 3) Install components (agreety may not exist on Manjaro)
wait_unlock; "$PAC" -S --noconfirm --needed seatd greetd || true
wait_unlock; "$PAC" -S --noconfirm --needed greetd-tuigreet || true
wait_unlock; "$PAC" -S --noconfirm --needed agreety || true

# 4) Enable seatd
systemctl enable --now seatd.service || true

# 5) Greeter user/groups
id -u greeter >/dev/null 2>&1 || useradd -M -s /bin/bash greeter || true
usermod -aG video,input greeter || true
getent group seat >/dev/null 2>&1 && usermod -aG seat greeter || true

# 6) Reserve VT for greetd (we use tty2)
systemctl mask getty@tty2.service || true

# 7) Success → write stamp last
install -D -m 0644 /dev/null /var/lib/sysclone/.layer2.5-greetd-installed
echo "[layer2.5] greetd/seatd configured"
# -- sysclone-l25-enable-greetd --

systemctl daemon-reload || true

systemctl enable --now greetd.service || true

# optional: avoid VT1 race with getty

systemctl disable --now getty.service 2>/dev/null || true

systemctl mask getty.service 2>/dev/null || true

