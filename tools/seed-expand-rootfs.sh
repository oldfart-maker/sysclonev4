#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[layer1] $*"; }

ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

install -d -m 0755 "$ROOT_MNT/usr/local/sbin" "$ROOT_MNT/etc/systemd/system" "$ROOT_MNT/var/lib/sysclone"

# Installer script that runs on the Pi at first boot
cat > "$ROOT_MNT/usr/local/sbin/sysclone-expand-rootfs.sh" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[expand-rootfs] $*"; }

STAMP=/var/lib/sysclone/.rootfs-expanded
[ -e "$STAMP" ] && { log "already expanded"; exit 0; }

# Find root block device
root_src="$(findmnt -n -o SOURCE / || true)"
case "$root_src" in
  /dev/*[0-9]) part="$root_src" ;;
  /dev/*)      # e.g., LVM; unsupported safely
               log "WARN: root is not a simple partition ($root_src); skipping resize"
               touch "$STAMP"; exit 0 ;;
  *)           log "ERROR: cannot determine root partition"; exit 1 ;;
esac

disk="$(lsblk -no PKNAME "$part" | sed 's/^/\/dev\//')"
if command -v growpart >/dev/null 2>&1; then
  log "growing partition: disk=$disk part=$part"
  # Extract the partition number (digits at end)
  pnum="$(echo "$part" | sed -E 's/.*[^0-9]([0-9]+)$/\1/')"
  growpart "$disk" "$pnum" || { log "growpart failed"; exit 1; }
else
  log "growpart not present; attempting resize2fs only"
fi

# Finally grow filesystem
log "running resize2fs on $part"
resize2fs "$part"

touch "$STAMP"
log "done"
EOS
chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-expand-rootfs.sh"

# Systemd unit (runs early, once)
cat > "$ROOT_MNT/etc/systemd/system/sysclone-expand-rootfs.service" <<'EOS'
[Unit]
Description=SysClone: Expand root filesystem to fill device
DefaultDependencies=no
After=local-fs.target
Before=multi-user.target
ConditionPathExists=!/var/lib/sysclone/.rootfs-expanded

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-expand-rootfs.sh

[Install]
WantedBy=multi-user.target
EOS

# Enable the unit
ln -sf ../sysclone-expand-rootfs.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-expand-rootfs.service" 2>/dev/null || true

log "staged sysclone-expand-rootfs.service + script"
