#!/usr/bin/env bash
set -euo pipefail

# 1) Make the oneshot installer enable seatd+greetd and mask getty@tty1
INS=tools/payloads/usr-local-sbin/sysclone-layer2.5-greetd-install.sh
grep -q 'sysclone-l25-enable-greetd' "$INS" || {
  printf '\n# -- sysclone-l25-enable-greetd --\n' >> "$INS"
  cat >> "$INS" <<'EOF'
systemctl daemon-reload || true
# seatd is required for greetd to own the seat
systemctl enable --now seatd.service || true
# bring up greetd
systemctl enable --now greetd.service || true
# avoid VT1 race with getty
systemctl disable --now getty@tty1.service 2>/dev/null || true
systemctl mask getty@tty1.service 2>/dev/null || true
EOF
  chmod +x "$INS"
  echo "[l2.5] appended enable steps to $INS"
}

# 2) Add a Makefile helper to clear the L2.5 stamp on target rootfs
if ! grep -q '^clear-layer2\.5-stamps:' Makefile; then
  cat >> Makefile <<'EOF'

# ---------------- Layer 2.5 maintenance ----------------
clear-layer2.5-stamps: ensure-mounted ## Clear L2.5 greetd stamp on target rootfs
	@echo "[clear:l2.5] removing greetd stamp"
	sudo rm -f $(ROOT_MNT)/var/lib/sysclone/.layer2.5-greetd-installed
EOF
  echo "[l2.5] added clear-layer2.5-stamps target to Makefile"
fi
