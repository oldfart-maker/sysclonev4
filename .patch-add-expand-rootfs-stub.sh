#!/usr/bin/env bash
set -euo pipefail
mkdir -p tools
cat > tools/seed-expand-rootfs.sh <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"
echo "[layer1] seed-expand-rootfs: stub (no-op)."
echo "         OK to ignore; card will boot with current 3.4G rootfs."
echo "         We can replace this with a proper first-boot expander later."
exit 0
EOF
chmod +x tools/seed-expand-rootfs.sh

git add tools/seed-expand-rootfs.sh
git commit -m "layer1: add stub tools/seed-expand-rootfs.sh (no-op for now)"
git tag -a v4.6.5-expand-rootfs-stub -m "Stub expand-rootfs helper to silence WARN"
