#!/usr/bin/env bash
set -euo pipefail

add_block() {
  local pattern="$1"
  local block="$2"
  grep -qE "$pattern" Makefile || printf "%s\n" "$block" >> Makefile
}

# ---- Layer 1 aggregate --------------------------------------------------------
add_block '^seed-layer1-all:' "$(cat <<'EOF'

# ---------------- Layer 1: aggregate ----------------
seed-layer1-all: ensure-mounted ## Layer1: disable first-boot + install first-boot service; leaves card unmounted
	@set -euo pipefail; \
	  $(MAKE) seed-layer1-disable-first-boot; \
	  $(MAKE) seed-layer1-first-boot-service; \
	  $(MAKE) ensure-unmounted; \
	  echo "[layer1] aggregate done"

.PHONY: seed-layer1-all
EOF
)"

# ---- Layer 2 aggregate --------------------------------------------------------
add_block '^seed-layer2-all:' "$(cat <<'EOF'

# ---------------- Layer 2: aggregate ----------------
seed-layer2-all: ensure-mounted ## Layer2: wayland providers + sway; leaves card unmounted
	@set -euo pipefail; \
	  $(MAKE) seed-layer2-wayland; \
	  $(MAKE) seed-layer2-sway; \
	  $(MAKE) ensure-unmounted; \
	  echo "[layer2] aggregate done"

.PHONY: seed-layer2-all
EOF
)"

# ---- Layer 2.5 aggregate ------------------------------------------------------
add_block '^seed-layer2\.5-all:' "$(cat <<'EOF'

# ---------------- Layer 2.5: aggregate ----------------
seed-layer2.5-all: ensure-mounted ## Layer2.5: greetd/tuigreet; leaves card unmounted
	@set -euo pipefail; \
	  $(MAKE) seed-layer2.5-greetd; \
	  $(MAKE) ensure-unmounted; \
	  echo "[layer2.5] aggregate done"

.PHONY: seed-layer2.5-all
EOF
)"

echo "[ok] aggregates appended (if missing)"
