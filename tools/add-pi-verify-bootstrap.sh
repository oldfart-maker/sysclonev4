#!/usr/bin/env bash
set -Eeuo pipefail
PI_MK="tools/payloads/usr-local-share/sysclone-pi.mk"
mkdir -p "$(dirname "$PI_MK")"
touch "$PI_MK"

# Already present?
grep -q '^# >>> verify-layer1-bootstrap' "$PI_MK" && { echo "[add] already present"; exit 0; }

cat >>"$PI_MK" <<'MK'

# >>> verify-layer1-bootstrap
.PHONY: verify verify-layer1-bootstrap
# 'verify' convenience runs both bootstrap + first-boot checks
verify: verify-layer1-bootstrap verify-layer1-install

verify-layer1-bootstrap:
	@set -euo pipefail; \
	fails=0; \
	echo "[verify] net bootstrap unit enabled?"; \
	if systemctl list-unit-files | grep -q '^sysclone-net-bootstrap\.service.*enabled'; then echo "  OK enabled"; else echo "  FAIL not enabled"; fails=1; fi; \
	echo "[verify] net bootstrap stamp? (/var/lib/sysclone/net-bootstrap.done)"; \
	if [[ -f /var/lib/sysclone/net-bootstrap.done ]]; then echo "  OK stamp"; else echo "  FAIL missing stamp"; fails=1; fi; \
	echo "[verify] keyring usable?"; \
	if pacman-key --list-keys >/dev/null 2>&1; then echo "  OK keyring"; else echo "  FAIL keyring not initialized"; fails=1; fi; \
	echo "[verify] mirrors/DB sync (pacman -Syy)"; \
	if pacman -Syy --noconfirm >/dev/null 2>&1; then echo "  OK pacman -Syy"; else echo "  FAIL pacman -Syy"; fails=1; fi; \
	echo "[verify] time sync (timedatectl)"; \
	if timedatectl 2>/dev/null | grep -q 'System clock synchronized: yes'; then echo "  OK time"; else echo "  WARN: time not confirmed (chrony/ntp)"; fi; \
	echo "[verify] make present?"; \
	if command -v make >/dev/null 2>&1; then echo "  OK make"; else echo "  FAIL: make missing"; fails=1; fi; \
	echo "[verify] summary: $${fails} failure(s)"; \
	exit $${fails}
# <<< verify-layer1-bootstrap
MK
echo "[add] appended verify-layer1-bootstrap to $PI_MK"
