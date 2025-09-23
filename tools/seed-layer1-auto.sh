#!/usr/bin/env bash
set -euo pipefail

USER_NAME="${USER:-username}"
SRC="seeds/layer1/first-boot.sh"
[[ -f "$SRC" ]] || { echo "[seed] ERROR: $SRC not found" >&2; exit 1; }

# 1) If a BOOT-ish VFAT is already mounted, use it
BOOT_MOUNT=""
while read -r name mnt fstype label; do
  [[ -n "$mnt" ]] || continue
  case "$fstype" in vfat|fat|fat16|fat32) ;; *) continue ;; esac
  if [[ "$label" =~ (BOOT|MNJRO|system-boot|boot) ]]; then
    BOOT_MOUNT="$mnt"
    found="pre-mounted:$label"
    break
  fi
done < <(lsblk -pnro NAME,MOUNTPOINT,FSTYPE,LABEL)

# Helper: verify a mount looks like RPi BOOT
looks_like_boot() {
  local dir="$1"
  [[ -f "$dir/config.txt" || -f "$dir/cmdline.txt" || -f "$dir/start4.elf" || -d "$dir/overlays" ]]
}

# Helper: try mount a device into a temp BOOT mountpoint
try_mount() {
  local dev="$1"
  local mnt="/run/media/${USER_NAME}/BOOT"
  sudo mkdir -p "$mnt"
  if sudo mount -o uid="$(id -u)",gid="$(id -g)" "$dev" "$mnt" 2>/dev/null; then
    if looks_like_boot "$mnt"; then
      echo "$dev" > "$mnt/.sysclone-mounted-dev"
      BOOT_MOUNT="$mnt"
      return 0
    fi
    sudo umount "$mnt" || true
  fi
  return 1
}

# 2) Try recorded UUID first (deterministic) if present
if [[ -z "$BOOT_MOUNT" && -f .state/boot-uuid ]]; then
  uuid="$(< .state/boot-uuid)"
  if [[ -n "$uuid" ]]; then
    dev="$(blkid -U "$uuid" 2>/dev/null || true)"
    [[ -n "$dev" ]] && try_mount "$dev" && found="uuid:$uuid"
  fi
fi

# 3) Try well-known labels next
if [[ -z "$BOOT_MOUNT" ]]; then
  for lbl in BOOT_MNJRO BOOT system-boot boot; do
    dev="$(blkid -L "$lbl" 2>/dev/null || true)"
    [[ -n "$dev" ]] && try_mount "$dev" && { found="label:$lbl"; break; }
  done
fi

# 4) Prefer vfat with boot-ish label, then any vfat/fat
if [[ -z "$BOOT_MOUNT" ]]; then
  mapfile -t candidates < <(lsblk -pnro NAME,FSTYPE,LABEL | awk 'BEGIN{IGNORECASE=1} $2 ~ /^(vfat|fat|fat16|fat32)$/ && $3 ~ /boot|mnjro/ {print $1}')
  mapfile -t others    < <(lsblk -pnro NAME,FSTYPE      | awk '$2 ~ /^(vfat|fat|fat16|fat32)$/ {print $1}')
  for dev in "${candidates[@]}" "${others[@]}"; do
    [[ -n "$dev" ]] || continue
    try_mount "$dev" && { found="scan:$dev"; break; }
  done
fi

if [[ -z "$BOOT_MOUNT" ]]; then
  echo "[seed] ERROR: could not auto-mount BOOT (FAT/VFAT)." >&2
  echo "[seed] Tips:" >&2
  echo "  sudo mkdir -p /run/media/$USER/BOOT" >&2
  echo "  sudo mount -o uid=$(id -u),gid=$(id -g) -L BOOT_MNJRO /run/media/$USER/BOOT" >&2
  echo "  # or: pick from lsblk -pno NAME,SIZE,FSTYPE,LABEL,PARTLABEL" >&2
  exit 1
fi

echo "[seed] Using BOOT: $BOOT_MOUNT (${found:-pre-mounted})"
install -Dm644 "$SRC" "$BOOT_MOUNT/sysclone-first-boot.sh"
cat > "$BOOT_MOUNT/README-sysclone.txt" <<'TXT'
SysClone v4 Layer1 seed

On the Pi (after first boot):
  sudo install -Dm755 /boot/sysclone-first-boot.sh /usr/local/sbin/sysclone-first-boot.sh
  sudo /usr/local/sbin/sysclone-first-boot.sh
TXT
echo "[seed] Seed complete."

if [[ -f "$BOOT_MOUNT/.sysclone-mounted-dev" ]]; then
  dev="$(cat "$BOOT_MOUNT/.sysclone-mounted-dev" || true)"
  rm -f "$BOOT_MOUNT/.sysclone-mounted-dev"
  echo "[seed] Sync + unmount ($dev)"
  sync
  sudo umount "$BOOT_MOUNT"
fi

# --- sysclone: optional Wi-Fi credential injection (post-copy) ---
if [[ -n "${WIFI_SSID:-}" && -n "${WIFI_PASS:-}" && -f "$BOOT_MOUNT/sysclone-first-boot.sh" ]]; then
  echo "[seed] injecting WIFI_SSID/WIFI_PASS into sysclone-first-boot.sh (SSID=${WIFI_SSID})"
  tmp="$BOOT_MOUNT/.sysclone-first-boot.sh.tmp"
  {
    head -n1 "$BOOT_MOUNT/sysclone-first-boot.sh"
    # printf %q yields shell-safe literals, so spaces/quotes are handled
    printf 'WIFI_SSID=%q\nWIFI_PASS=%q\n' "$WIFI_SSID" "$WIFI_PASS"
    tail -n +2 "$BOOT_MOUNT/sysclone-first-boot.sh"
  } > "$tmp"
  mv -f "$tmp" "$BOOT_MOUNT/sysclone-first-boot.sh"
  sync
fi
# --- end injection ---
