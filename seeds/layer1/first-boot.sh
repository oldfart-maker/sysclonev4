#!/usr/bin/env bash
set -Eeuo pipefail

# -------- Config flags (all optional except --user for user creation) --------
 make clone-pi DEV=/dev/sdc WIFI_SSID='ATT6Syj7QR' WIFI_PSK='8ks#764g3bh6'
HOSTNAME="archpi5"
NEW_USER="username"
NEW_USER_PASS="username"
SUDO_MODE="wheel"        # wheel | passwordless
WIFI_SSID="ATT6Syj7QR"
WIFI_PASS="8ks#764g3bh6"
TZ_REGION="America/New York"
NET_ONLINE_TIMEOUT=45    # seconds

usage() {
  cat <<'USAGE'
Usage: l1-first-boot.sh [options]

  --hostname NAME          Hostname to set (default: archpi5)
  --user NAME              Create this user and add to 'wheel'
  --user-pass PASS         Set user password (optional)
  --sudo-mode MODE         'wheel' (passworded sudo) or 'passwordless'
  --wifi-ssid SSID         Optional Wi-Fi SSID to provision (iwd)
  --wifi-pass PASS         Optional Wi-Fi passphrase
  --tz ZONE                Timezone (default: America/Chicago)
  --net-timeout SECONDS    Wait time for network-online (default: 45)
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hostname) HOSTNAME="$2"; shift 2;;
    --user) NEW_USER="$2"; shift 2;;
    --user-pass) NEW_USER_PASS="$2"; shift 2;;
    --sudo-mode) SUDO_MODE="$2"; shift 2;;
    --wifi-ssid) WIFI_SSID="$2"; shift 2;;
    --wifi-pass) WIFI_PASS="$2"; shift 2;;
    --tz) TZ_REGION="$2"; shift 2;;
    --net-timeout) NET_ONLINE_TIMEOUT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

as_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "[L1] run as root"; exit 1; }; }
pac() { pacman --noconfirm --needed "$@"; }
write_file() { local m="$1" p="$2"; shift 2; install -D -m "$m" /dev/null "$p"; cat >"$p"; }
ensure_line() { local f="$1" line="$2"; install -D -m 0644 "$f" "$f" 2>/dev/null || true; grep -qxF -- "$line" "$f" || echo "$line" >>"$f"; }

setup_network() {
  # networkd: ethernet + wlan DHCP
  write_file 0644 /etc/systemd/network/10-ethernet.network <<'EOFN1'
[Match]
Name=e* en* eth*
[Network]
DHCP=yes
EOFN1

  write_file 0644 /etc/systemd/network/20-wlan.network <<'EOFN2'
[Match]
Name=wlan*
[Network]
DHCP=yes
EOFN2

  # iwd: auth only; no IP config
  write_file 0644 /etc/iwd/main.conf <<'EOFIWD'
[General]
EnableNetworkConfiguration=false
AutoConnect=true
EOFIWD

  # resolv.conf -> resolved stub
  ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

  systemctl enable systemd-networkd.service
  systemctl enable systemd-resolved.service
  systemctl enable systemd-timesyncd.service
  systemctl enable iwd.service
  systemctl enable systemd-networkd-wait-online.service
}

provision_wifi() {
  [[ -z "$WIFI_SSID" ]] && return 0
  [[ -z "$WIFI_PASS" ]] && { echo "[L1] --wifi-ssid set but --wifi-pass missing"; return 1; }
  install -d -m 700 /var/lib/iwd
  write_file 0600 "/var/lib/iwd/${WIFI_SSID}.psk" <<EOFPSK
[Security]
Passphrase=${WIFI_PASS}
EOFPSK
  echo "[L1] provisioned iwd PSK for '${WIFI_SSID}'"
}

wait_network_online() {
  echo "[L1] waiting up to ${NET_ONLINE_TIMEOUT}s for network-online…"
  if ! timeout "${NET_ONLINE_TIMEOUT}"s bash -c 'until systemctl is-active --quiet network-online.service; do sleep 1; done'; then
    echo "[L1] WARN: network-online not reached; continuing"
  else
    echo "[L1] network-online reached"
  fi
}

setup_user_sudo() {
  [[ -z "$NEW_USER" ]] && return 0
  if ! id -u "$NEW_USER" >/dev/null 2>&1; then
    useradd -m -G wheel -s /bin/bash "$NEW_USER"
    [[ -n "$NEW_USER_PASS" ]] && echo "${NEW_USER}:${NEW_USER_PASS}" | chpasswd
    echo "[L1] created user '$NEW_USER' in wheel"
  else
    usermod -aG wheel "$NEW_USER" || true
  fi

  case "$SUDO_MODE" in
    passwordless)
      write_file 0440 /etc/sudoers.d/10-wheel-nopasswd <<'EOFS'
%wheel ALL=(ALL) NOPASSWD: ALL
EOFS
      ;;
    wheel|*)
      # ensure stock wheel line is active
      sed -i 's/^#\s*\(%wheel\s\+ALL=(ALL:ALL)\s\+ALL\)/\1/' /etc/sudoers || true
      ;;
  esac
}

setup_system_id() {
  echo "$HOSTNAME" >/etc/hostname
  timedatectl set-timezone "$TZ_REGION" || true
  timedatectl set-ntp true || true
  ensure_line /etc/locale.gen "en_US.UTF-8 UTF-8"
  locale-gen
  write_file 0644 /etc/locale.conf <<'EOFL'
LANG=en_US.UTF-8
LC_TIME=en_US.UTF-8
EOFL
}

main() {
  as_root
  echo "[L1] pacman -Syu"
  pac -Syu
  echo "[L1] install base packages"
  pac -S base-devel git sudo openssh iwd vim curl
  echo "[L1] enable sshd"
  systemctl enable sshd.service
  echo "[L1] configure network stack"
  setup_network
  provision_wifi
  echo "[L1] hostname/locale/time"
  setup_system_id
  echo "[L1] user/sudo"
  setup_user_sudo
  echo "[L1] wait for network-online"
  wait_network_online
  echo "[L1] done. You can: systemctl reboot"
}
main "$@"
