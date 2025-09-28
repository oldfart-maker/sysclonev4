#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[layer1] $*"; }
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

install -d -m 0755 \
  "$ROOT_MNT/usr/local/sbin" \
  "$ROOT_MNT/etc/systemd/system" \
  "$ROOT_MNT/var/lib/sysclone"

cat > "$ROOT_MNT/usr/local/sbin/sysclone-expand-rootfs.sh" <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
log(){ echo "[expand-rootfs] $*"; }

STAMP_DONE=/var/lib/sysclone/.rootfs-expanded
STAMP_P1=/var/lib/sysclone/.rootfs-phase1-done

[ -e "$STAMP_DONE" ] && { log "already expanded"; exit 0; }

root_src="$(findmnt -n -o SOURCE / || true)"
case "$root_src" in
  /dev/*[0-9]) part="$root_src" ;;
  /dev/*)      log "WARN: complex root ($root_src); stamping done"; touch "$STAMP_DONE"; exit 0 ;;
  *)           log "ERROR: cannot determine root partition"; exit 1 ;;
esac

disk="$(lsblk -no PKNAME "$part" | sed 's/^/\/dev\//')"
pnum="$(echo "$part" | sed -E 's/.*[^0-9]([0-9]+)$/\1/')"
[ -n "$pnum" ] || { log "ERROR: could not parse partition number from $part"; exit 1; }

if [ ! -e "$STAMP_P1" ]; then
  log "phase1: extend partition to 100%"
  if command -v growpart >/dev/null 2>&1; then
    log "branch=growpart disk=$disk part=$part pnum=$pnum"
    growpart "$disk" "$pnum" || { log "growpart failed"; exit 1; }
  elif command -v parted >/dev/null 2>&1; then
    log "branch=parted disk=$disk part=$part pnum=$pnum (resizepart -> 100%)"
    parted -s "$disk" ---pretend-input-tty <<CMD || true
unit %
print
resizepart $pnum 100%
Yes
print
CMD
  else
    log "ERROR: no growpart/parted available"; exit 1
  fi

  command -v partprobe >/dev/null 2>&1 && { log "partprobe $disk"; partprobe "$disk" || true; }
  command -v udevadm   >/dev/null 2>&1 && { log "udevadm settle"; udevadm settle || true; }
  sleep 1

  log "phase1 complete; stamping and rebooting once for kernel to re-read table"
  touch "$STAMP_P1"
  systemctl reboot
  exit 0
fi

log "phase2: grow filesystem on $part"
resize2fs "$part"

touch "$STAMP_DONE"
log "done"
EOT
chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-expand-rootfs.sh"

cat > "$ROOT_MNT/etc/systemd/system/sysclone-expand-rootfs.service" <<'EOT'
[Unit]
Description=SysClone: Expand root filesystem to fill device (two-phase)
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

ln -sf ../sysclone-expand-rootfs.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-expand-rootfs.service" 2>/dev/null || true

log "staged sysclone-expand-rootfs (two-phase)"
