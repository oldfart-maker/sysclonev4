#!/usr/bin/env bash
set -euo pipefail

mkdir -p tools/payloads/usr-local-sbin tools/payloads/etc-systemd-system seeds/layer1

# 1) Payload: /usr/local/sbin/sysclone-expand-rootfs.sh
cat > tools/payloads/usr-local-sbin/sysclone-expand-rootfs.sh <<'EOF'
#!/usr/bin/env bash
# Expand rootfs on first boot (ext4/btrfs/xfs supported)
set -euo pipefail

log(){ echo "[expand-rootfs] $*"; }

STAMP="/var/lib/sysclone/.rootfs-expanded"
mkdir -p "$(dirname "$STAMP")"

if [[ -e "$STAMP" ]]; then
  log "already expanded; exiting"
  exit 0
fi

# Resolve root partition device (works for /dev/root, PARTUUID=…, etc.)
root_src="$(findmnt -rno SOURCE / || true)"
if [[ -z "${root_src:-}" || "$root_src" == "/dev/root" ]]; then
  # Try by PARTUUID from /proc/cmdline
  PART_ARG="$(sed -n 's/.*root=\([^ ]*\).*/\1/p' /proc/cmdline || true)"
  if [[ "$PART_ARG" =~ ^PARTUUID= ]]; then
    byp="/dev/disk/by-partuuid/${PART_ARG#PARTUUID=}"
    root_src="$(realpath "$byp" 2>/dev/null || true)"
  elif [[ "$PART_ARG" =~ ^UUID= ]]; then
    byu="/dev/disk/by-uuid/${PART_ARG#UUID=}"
    root_src="$(realpath "$byu" 2>/dev/null || true)"
  fi
fi

if [[ -z "${root_src:-}" || ! -b "$root_src" ]]; then
  log "ERROR: cannot resolve root block device (got: '$root_src')"
  exit 1
fi

# Identify disk + partition number
disk="/dev/$(lsblk -nro PKNAME "$root_src")"
partnum="$(lsblk -nro PARTNUM "$root_src")"
fstype="$(findmnt -rno FSTYPE / || true)"

if [[ -z "$disk" || -z "$partnum" ]]; then
  log "ERROR: cannot determine disk/partnum for $root_src"
  exit 1
fi

log "root_src=$root_src disk=$disk partnum=$partnum fstype=${fstype:-unknown}"

# Grow the partition to the end of the device
if command -v growpart >/dev/null 2>&1; then
  log "using growpart"
  sudo growpart "$disk" "$partnum"
else
  # Prefer parted if available; fallback to sfdisk -N
  if command -v parted >/dev/null 2>&1; then
    log "using parted resizepart -> 100%"
    sudo parted -s "$disk" -- \
      unit % print \
      resizepart "$partnum" 100%
  else
    log "using sfdisk -N (extend to end)"
    # Note: sfdisk extends when size is left empty
    echo ",+" | sudo sfdisk -N "$partnum" "$disk"
  fi
fi

# Re-read partition table & settle
if command -v partprobe >/dev/null 2>&1; then
  sudo partprobe "$disk" || true
fi
sudo udevadm settle || true

# Grow filesystem online
case "${fstype:-}" in
  ext4)
    log "resize2fs on $root_src"
    sudo resize2fs "$root_src"
    ;;
  btrfs)
    log "btrfs resize max /"
    sudo btrfs filesystem resize max /
    ;;
  xfs)
    log "xfs_growfs /"
    sudo xfs_growfs /
    ;;
  *)
    log "WARN: unsupported/unknown fstype '${fstype:-?}', skipping FS grow"
    ;;
esac

date -u +"%F %T UTC" | sudo tee "$STAMP" >/dev/null
log "done; stamped $STAMP"
EOF
chmod +x tools/payloads/usr-local-sbin/sysclone-expand-rootfs.sh

# 2) Unit file: /etc/systemd/system/sysclone-expand-rootfs.service
cat > tools/payloads/etc-systemd-system-sysclone-expand-rootfs.service <<'EOF'
[Unit]
Description=SysClone: Expand root filesystem on first boot
DefaultDependencies=no
After=local-fs-pre.target
Before=multi-user.target
ConditionPathExists=!/var/lib/sysclone/.rootfs-expanded

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-expand-rootfs.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# 3) Seeder to stage the files onto the mounted rootfs
cat > seeds/layer1/seed-expand-rootfs.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT_MNT:-/mnt/sysclone-root}"

log(){ echo "[seed:l1] $*"; }

[[ -d "$ROOT/etc" ]] || { echo "[seed:l1] ERR: $ROOT not mounted"; exit 2; }

install -D -m 0755 tools/payloads/usr-local-sbin/sysclone-expand-rootfs.sh \
  "$ROOT/usr/local/sbin/sysclone-expand-rootfs.sh"

install -D -m 0644 tools/payloads/etc-systemd-system-sysclone-expand-rootfs.service \
  "$ROOT/etc/systemd/system/sysclone-expand-rootfs.service"

ln -sfn ../sysclone-expand-rootfs.service \
  "$ROOT/etc/systemd/system/multi-user.target.wants/sysclone-expand-rootfs.service"

echo "[seed:l1] staged expand-rootfs unit + script (enabled)"
EOF
chmod +x seeds/layer1/seed-expand-rootfs.sh

# 4) Makefile target (append if absent)
if ! grep -q '^seed-layer1-expand-rootfs:' Makefile; then
  cat >> Makefile <<'EOF'

# Layer1: expand rootfs on first boot (enable oneshot unit)
seed-layer1-expand-rootfs: ensure-mounted ## Stage first-boot rootfs expansion unit/script
	@sudo env ROOT_MNT="$(ROOT_MNT)" bash seeds/layer1/seed-expand-rootfs.sh
	@$(MAKE) ensure-unmounted
.PHONY: seed-layer1-expand-rootfs
EOF
fi

git add -A
git commit -m "layer1: add first-boot rootfs expansion (oneshot service + seeder)"
git tag -a v4.6.0-expand-rootfs -m "Layer1: add sysclone-expand-rootfs (grow part2 + resize fs on first boot)"
echo "[ok] committed + tagged v4.6.0-expand-rootfs"
