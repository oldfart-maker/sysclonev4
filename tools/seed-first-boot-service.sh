#!/usr/bin/env bash
set -Eeuo pipefail
log(){ [[ "${QUIET:-0}" = "1" ]] || echo "[install:l1] $*"; }

# ----- inputs / fallbacks -----
BOOT_MOUNT="${BOOT_MOUNT:-/mnt/sysclone-boot}"
ROOT_MOUNT="${ROOT_MOUNT:-/mnt/sysclone-root}"
BOOT_LABEL="${BOOT_LABEL:-BOOT_MNJRO}"
ROOT_LABEL="${ROOT_LABEL:-ROOT_MNJRO}"
DEVICE="${DEVICE:-}"

# allow values from Makefile env or tools/.env
if [[ -f "./tools/.env" ]]; then . "./tools/.env"; fi
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASS="${WIFI_PASS:-}"
USERNAME="${USERNAME:-username}"
USERPASS="${USERPASS:-username}"

# ----- resolve partitions by DEVICE or by-label -----
if [[ -n "$DEVICE" ]]; then
  if [[ "$DEVICE" =~ (mmcblk|nvme) ]]; then
    BOOT_PART="${DEVICE}p1"; ROOT_PART="${DEVICE}p2"
  else
    BOOT_PART="${DEVICE}1";  ROOT_PART="${DEVICE}2"
  fi
else
  BOOT_PART="/dev/disk/by-label/${BOOT_LABEL}"
  ROOT_PART="/dev/disk/by-label/${ROOT_LABEL}"
fi

# ----- mount (idempotent) -----
sudo mkdir -p "$BOOT_MOUNT" "$ROOT_MOUNT"
if ! mountpoint -q "$ROOT_MOUNT"; then sudo mount "$ROOT_PART" "$ROOT_MOUNT"; fi
if [[ -e "$BOOT_PART" ]] && ! mountpoint -q "$BOOT_MOUNT"; then sudo mount "$BOOT_PART" "$BOOT_MOUNT" || true; fi

log "BOOT=${BOOT_PART:-N/A} mounted at $BOOT_MOUNT"
log "ROOT=$ROOT_PART mounted at $ROOT_MOUNT"

# ----- install payloads to ROOT -----
sudo install -Dm755 seeds/layer1/first-boot-provision.sh \
  "$ROOT_MOUNT/usr/local/lib/sysclone/first-boot-provision.sh"
sudo install -Dm644 seeds/layer1/first-boot.service \
  "$ROOT_MOUNT/etc/systemd/system/sysclone-first-boot.service"

# ----- write /etc/sysclone/firstboot.env on ROOT (quoted) -----
sudo install -d -m 0755 "$ROOT_MOUNT/etc/sysclone"
sudo tee "$ROOT_MOUNT/etc/sysclone/firstboot.env" >/dev/null <<EOF
WIFI_SSID='${WIFI_SSID}'
WIFI_PASS='${WIFI_PASS}'
USERNAME='${USERNAME}'
USERPASS='${USERPASS}'
EOF
sudo chmod 0640 "$ROOT_MOUNT/etc/sysclone/firstboot.env" || true

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
head -n1 seeds/layer1/first-boot.sh > "$tmp"
printf 'WIFI_SSID=%q\nWIFI_PASS=%q\n' "$WIFI_SSID" "$WIFI_PASS" >> "$tmp"
tail -n +2 seeds/layer1/first-boot.sh >> "$tmp"

if [[ -e "$BOOT_PART" ]]; then
  sudo cp --remove-destination --no-preserve=mode,ownership,timestamps \
    "$tmp" "$BOOT_MOUNT/sysclone-first-boot.sh"
  sudo chmod 0755 "$BOOT_MOUNT/sysclone-first-boot.sh" || true
  # Also install a real copy into the target rootfs where the provisioner expects it.
  sudo install -D -m 0755 "$tmp" "$ROOT_MOUNT/usr/local/sbin/sysclone-first-boot.sh"
  sync
  log "wrote BOOT:/sysclone-first-boot.sh (with SSID=${WIFI_SSID:-<empty>})"
else
  log "WARN: BOOT partition not present; skipped copying sysclone-first-boot.sh"
fi

# ----- enable unit on ROOT -----
sudo mkdir -p "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants"
sudo ln -sf ../sysclone-first-boot.service \
  "$ROOT_MOUNT/etc/systemd/system/multi-user.target.wants/sysclone-first-boot.service"

log "unit enabled; payloads staged"

# ----- unmount (idempotent) -----
sudo umount "$ROOT_MOUNT" || true
if [[ -e "$BOOT_PART" ]]; then sudo umount "$BOOT_MOUNT" || true; fi
log "done"
