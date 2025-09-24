#!/usr/bin/env bash
set -Eeuo pipefail
log(){ printf '%s %s\n' "[FIRST-BOOT]" "$*"; }

# 1) timezone
log "set timezone to America/New_York"
timedatectl set-timezone America/New_York

# 2) user "username" with password "username"
if ! id -u username >/dev/null 2>&1; then
  log "create user 'username' with wheel sudo"
  useradd -m -G wheel -s /bin/bash username
  echo 'username:username' | chpasswd
else
  log "user 'username' already exists"
fi

# ensure wheel sudoers is enabled
if grep -Eq '^\s*#\s*%wheel\s+ALL=\(ALL:ALL\)\s+ALL' /etc/sudoers; then
  log "enable wheel in sudoers"
  sed -i -E 's/^\s*#\s*(%wheel\s+ALL=\(ALL:ALL\)\s+ALL)/\1/' /etc/sudoers
fi

# 3) keyboard layout
log "set keymap to us"
localectl set-keymap us

# 4) locale
log "enable en_US.UTF-8 in /etc/locale.gen and set LANG"
sed -i -E 's/^#\s*en_US\.UTF-8\s+UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
localectl set-locale LANG=en_US.UTF-8

# 5) hostname
log "set hostname to archpi5"
hostnamectl set-hostname archpi5

# 6) run sysclone-first-boot.sh if present
if [[ -x /usr/local/sbin/sysclone-first-boot.sh ]]; then
  log "run /usr/local/sbin/sysclone-first-boot.sh"
  /usr/local/sbin/sysclone-first-boot.sh || log "sysclone-first-boot.sh exited nonzero"
else
  log "WARN: /usr/local/sbin/sysclone-first-boot.sh not found or not executable"
fi

# stamp + self-disable
install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/first-boot.done
log "disabling systemd unit so it won't run again"
systemctl disable sysclone-first-boot.service || true

log "first-boot provisioning complete"
