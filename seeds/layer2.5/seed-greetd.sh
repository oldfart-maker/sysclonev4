#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT_MNT:?ROOT_MNT not set}"

echo "[seed] layer2.5: greetd (agreety) + config"

# stage an on-boot installer OR directly copy (no chroot on host)
install -D -m0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"

# ensure greetd is enabled on target; if we can't chroot here, stage a oneshot
if command -v arch-chroot >/dev/null 2>&1; then
  sudo arch-chroot "$ROOT" bash -ec '
    set -euo pipefail
    pacman -Sy --noconfirm greetd
    systemctl enable greetd.service
  '
else
  # on-boot oneshot to install/enable greetd on the Pi
  install -D -m0755 /dev/stdin "$ROOT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/sysclone-layer2.5.log
exec > >(tee -a "$LOG") 2>&1
echo "[layer2.5-install] install greetd (agreety)"
pacman -Syy --noconfirm greetd || true
systemctl enable greetd.service || true
install -d -m0755 /var/lib/sysclone
: > /var/lib/sysclone/.layer2.5-greetd-installed
echo "[layer2.5-install] done"
SCRIPT

  install -D -m0644 /dev/stdin "$ROOT/etc/systemd/system/sysclone-layer2.5-greetd-install.service" <<'UNIT'
[Unit]
Description=SysClone Layer 2.5 On-Boot Installer (greetd/agreety)
Wants=network-online.target time-sync.target
After=network-online.target time-sync.target
ConditionPathExists=!/var/lib/sysclone/.layer2.5-greetd-installed

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-layer2.5-greetd-install.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT

  ln -sf ../sysclone-layer2.5-greetd-install.service \
    "$ROOT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd-install.service"
fi

echo "[seed] layer2.5: greetd staged"
