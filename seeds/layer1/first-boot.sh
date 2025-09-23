#!/usr/bin/env bash
set -Eeuo pipefail

log() { printf '%s %s\n' "[L1]" "$*"; }

usage() {
  cat <<USAGE
Usage: $0 [--wifi-ssid SSID --wifi-pass PASS]
  --wifi-ssid   SSID for iwd
  --wifi-pass   Passphrase for iwd
USAGE
}

WIFI_SSID=""
WIFI_PASS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wifi-ssid) WIFI_SSID="${2-}"; shift 2;;
    --wifi-pass) WIFI_PASS="${2-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) log "WARN: unknown arg: $1"; shift;;
  esac
done

provision_wifi() {
  [[ -z "$WIFI_SSID" ]] && return 0
  if [[ -z "$WIFI_PASS" ]]; then
    log "--wifi-ssid set but --wifi-pass missing"
    return 1
  fi

  install -d -m 700 /var/lib/iwd
  cat > "/var/lib/iwd/${WIFI_SSID}.psk" <<EOFPSK
[Security]
Passphrase=${WIFI_PASS}
EOFPSK
  chmod 0600 "/var/lib/iwd/${WIFI_SSID}.psk"
  log "provisioned iwd PSK for '${WIFI_SSID}'"
}

connect_wifi() {
  # Only attempt when we have creds
  [[ -z "$WIFI_SSID" ]] && return 0
  [[ -z "$WIFI_PASS" ]] && { log "--wifi-ssid set but --wifi-pass missing (cannot connect)"; return 1; }

  # Make sure iwd is running
  sudo systemctl enable --now iwd >/dev/null 2>&1 || true

  # Pick first wlan interface
  local WLAN_IF
  WLAN_IF="$(iw dev | awk '/Interface/ {print $2; exit}')"
  if [[ -z "$WLAN_IF" ]]; then
    log "no wlan interface found (iw dev empty)"; return 1
  fi

  # Connect using iwctl (non-interactive)
  if sudo iwctl --passphrase "$WIFI_PASS" station "$WLAN_IF" connect "$WIFI_SSID"; then
    log "iwctl connect issued on $WLAN_IF to '$WIFI_SSID'"
  else
    log "iwctl connect failed on $WLAN_IF to '$WIFI_SSID'"
    return 1
  fi
}

main() {
  log "starting minimal first-boot"
  provision_wifi
  connect_wifi
  log "done"
}

main "$@"
