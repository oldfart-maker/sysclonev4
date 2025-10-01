#!/usr/bin/env bash
set -Eeuo pipefail

ENV_FILE="/etc/sysclone/firstboot.env"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  . "$ENV_FILE"
fi
set -u

: "${WIFI_SSID:=}"
: "${WIFI_PASS:=}"
: "${USERNAME:=username}"
: "${USERPASS:=username}"

log(){ printf '%s %s\n' "[L1]" "$*"; }

provision_wifi() {
  [[ -z "$WIFI_SSID" ]] && return 0
  [[ -z "$WIFI_PASS" ]] && { log "--wifi-ssid set but --wifi-pass missing"; return 1; }

  install -d -m 700 /var/lib/iwd
  cat > "/var/lib/iwd/${WIFI_SSID}.psk" <<EOF
[Security]
Passphrase=${WIFI_PASS}
EOF
  chmod 0600 "/var/lib/iwd/${WIFI_SSID}.psk"
  systemctl enable --now iwd >/dev/null 2>&1 || true
  # best effort connect
  if iw dev | awk '/Interface/ {print $2; exit}' | xargs -r -I{} iwctl --passphrase "$WIFI_PASS" station {} connect "$WIFI_SSID"; then
    log "wifi connect issued"
  else
    log "wifi connect failed (continuing)"
  fi
}

ensure_user_and_seatd() {
  # create user if missing
  if ! id -u "$USERNAME" >/dev/null 2>&1; then
    log "creating user '$USERNAME' (wheel)"
    useradd -m -G wheel -s /bin/bash "$USERNAME"
    echo "${USERNAME}:${USERPASS}" | chpasswd
    # enable wheel sudoers if commented
    sed -i -E 's/^\s*#\s*(%wheel\s+ALL=\(ALL:ALL\)\s+ALL)/\1/' /etc/sudoers
  fi

  # groups needed for Wayland/seatd
  for g in seat input video render; do
    getent group "$g" >/dev/null 2>&1 || groupadd -r "$g" || true
  done
  usermod -aG seat,input,video,render "$USERNAME" || true

  # seatd if available
  if systemctl list-unit-files --no-legend | grep -q '^seatd\.service'; then
    systemctl enable --now seatd.service || true
  fi

  log "seatd/groups ensured for $USERNAME"
}

main() {
  log "first-boot start"
  provision_wifi || true
  ensure_user_and_seatd
  log "first-boot done"
}
main "$@"
