#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[layer1] $*"; }
## Harden: always run parted resizepart 100%, log before/after, re-read table,
## and ensure the unit orders Before=sysclone-first-boot.service.

ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

install -d -m 0755 \
  "$ROOT_MNT/usr/local/sbin" \
  "$ROOT_MNT/etc/systemd/system" \
  "$ROOT_MNT/var/lib/sysclone"

# Installer script that runs on the Pi at first boot
cat > "$ROOT_MNT/usr/local/sbin/sysclone-expand-rootfs.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[expand-rootfs] $*"; }

STAMP=/var/lib/sysclone/.rootfs-expanded
[ -e "$STAMP" ] && { log "already expanded"; exit 0; }

# Find root block device
root_src="$(findmnt -n -o SOURCE / || true)"
case "$root_src" in
  /dev/*[0-9]) part="$root_src" ;;
  /dev/*)      log "WARN: root is not a simple partition ($root_src); stamping and skipping"; touch "$STAMP"; exit 0 ;;
  *)           log "ERROR: cannot determine root partition"; exit 1 ;;
esac

disk="$(lsblk -no PKNAME "$part" | sed 's/^/\/dev\//')"
pnum="$(echo "$part" | sed -E 's/.*[^0-9]([0-9]+)$/\1/')"
[ -n "$pnum" ] || { log "ERROR: could not parse partition number from $part"; exit 1; }

log "pre: lsblk"; lsblk -e7 -o NAME,SIZE,TYPE,MOUNTPOINTS || true
log "pre: parted print (disk=$disk)"; parted -s "$disk" unit s print || true

if command -v growpart >/dev/null 2>&1; then
  log "branch=growpart disk=$disk part=$part pnum=$pnum"
  growpart "$disk" "$pnum" || { log "growpart failed"; exit 1; }
else
  if command -v parted >/dev/null 2>&1; then
    log "branch=parted disk=$disk part=$part pnum=$pnum (resizepart -> 100%)"
    # Always attempt to extend to 100%; if already at end, parted will say so.
    parted -s "$disk" ---pretend-input-tty <<CMD || true
unit %
print
resizepart $pnum 100%
Yes
print
CMD
  else
    log "ERROR: neither growpart nor parted available; cannot grow partition"
    exit 1
  fi
fi

# Re-read the partition table / settle device nodes before growing FS
command -v partprobe >/dev/null 2>&1 && { log "running partprobe $disk"; partprobe "$disk" || true; }
command -v udevadm   >/dev/null 2>&1 && { log "running udevadm settle"; udevadm settle || true; }
sleep 1

log "post: lsblk"; lsblk -e7 -o NAME,SIZE,TYPE,MOUNTPOINTS || true
log "post: parted print (disk=$disk)"; parted -s "$disk" unit s print || true

# Finally grow filesystem
log "running resize2fs on $part"
resize2fs "$part"

touch "$STAMP"
log "done"
EOT
chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-expand-rootfs.sh"

# Systemd unit (runs early, once)
cat > "$ROOT_MNT/etc/systemd/system/sysclone-expand-rootfs.service" <<'EOT'
[Unit]
Description=SysClone: Expand root filesystem to fill device
DefaultDependencies=no
After=local-fs.target systemd-udev-settle.service
Before=sysclone-first-boot.service
ConditionPathExists=!/var/lib/sysclone/.rootfs-expanded

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-expand-rootfs.sh

[Install]
WantedBy=multi-user.target
EOT

# Enable the unit
ln -sf ../sysclone-expand-rootfs.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-expand-rootfs.service" 2>/dev/null || true

log "staged sysclone-expand-rootfs.service + script"
