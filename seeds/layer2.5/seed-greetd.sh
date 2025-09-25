#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT_MNT:?ROOT_MNT not set}"
echo "[seed] layer2.5: greetd (agreety) + config (ROOT=$ROOT)"

# 1) Copy greetd config (root-owned). Pre-remove to avoid sticky/attr edge cases.
sudo install -d -m0755 "$ROOT/etc/greetd"
sudo rm -f "$ROOT/etc/greetd/config.toml" || true
sudo install -m0644 tools/payloads/etc-greetd-config.toml \
  "$ROOT/etc/greetd/config.toml"

# 2) Install/enable greetd
if command -v arch-chroot >/dev/null 2>&1; then
  echo "[seed] layer2.5: installing greetd inside chroot"
  sudo arch-chroot "$ROOT" bash -ec '
    set -euo pipefail
    pacman -Syy --noconfirm greetd || true
    systemctl enable greetd.service || true
  '
else
  echo "[seed] layer2.5: staging on-boot greetd installer"
  # installer script on the target
  sudo install -D -m0755 /dev/stdin "$ROOT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
LOG=/var/log/sysclone-layer2.5.log
exec > >(tee -a "$LOG") 2>&1
echo "[layer2.5-install] pacman -Syy greetd"
pacman -Syy --noconfirm greetd || true
systemctl enable greetd.service || true
install -d -m0755 /var/lib/sysclone
: > /var/lib/sysclone/.layer2.5-greetd-installed
echo "[layer2.5-install] done"
SCRIPT

  # oneshot unit to run the installer at first boot
  sudo install -D -m0644 /dev/stdin "$ROOT/etc/systemd/system/sysclone-layer2.5-greetd-install.service" <<'UNIT'
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

  # enable the oneshot
  sudo ln -sf ../sysclone-layer2.5-greetd-install.service \
    "$ROOT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd-install.service"
fi

echo "[seed] layer2.5: done"
