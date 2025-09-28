SHELL := /bin/bash
.ONESHELL:
.DELETE_ON_ERROR:

# ---- Common helpers ----
unit_l1 := sysclone-first-boot.service
unit_l2 := sysclone-layer2-install.service
unit_l25 := sysclone-layer2.5-greetd-install.service
stamp_dir := /var/lib/sysclone

help:
	@echo "scpi targets:"
	@echo "  verify-layer1-install     - check files + journal for Layer1"
	@echo "  verify-layer2-install     - status/logs + mirror sanity for Layer2"
	@echo "  verify-layer2.5-install   - status/logs + greetd config for Layer2.5"
	@echo "  logs-layer2               - journal for Layer2"
	@echo "  logs-layer2.5             - journal for Layer2.5"
	@echo "  rerun-layer2-install      - clear stamp + start L2 oneshot"
	@echo "  rerun-layer2.5-install    - clear stamp + start L2.5 oneshot"

verify-layer1-install:
	@set -euo pipefail
	echo "[pi] L1 files"
	ls -l /etc/systemd/system/$(unit_l1) || true
	ls -l /etc/systemd/system/multi-user.target.wants/$(unit_l1) || true
	ls -l /usr/local/lib/sysclone/first-boot-provision.sh || true
	ls -l /usr/local/sbin/sysclone-first-boot.sh || true
	echo
	echo "[pi] firstboot.env (first 20 lines)"
	sed -n '1,20p' /etc/sysclone/firstboot.env || true
	echo
	echo "[pi] L1 journal (this boot)"
	journalctl -u $(unit_l1) -b --no-pager --no-hostname || true

verify-layer2-install:
	@set -euo pipefail
	echo "[pi] L2 status"
	systemctl status $(unit_l2) --no-pager || true
	echo
	echo "[pi] L2 journal (this boot)"
	journalctl -u $(unit_l2) -b --no-pager --no-hostname || true
	echo
	echo "[pi] mirrorlist head"
	sed -n '1,20p' /etc/pacman.d/mirrorlist || true

verify-layer2\.5-install:
	@set -euo pipefail
	echo "[pi] greetd + seatd status"
	systemctl is-enabled greetd || true
	systemctl status seatd --no-pager || true
	systemctl status greetd --no-pager || true
	echo
	echo "[pi] L2.5 journal (this boot)"
	journalctl -u $(unit_l25) -b --no-pager --no-hostname || true
	echo
	echo "[pi] greetd config + drop-ins"
	ls -l /etc/greetd/config.toml || true
	sed -n '1,80p' /etc/greetd/config.toml || true
	find /etc/systemd/system/greetd.service.d -maxdepth 1 -type f -printf "%f\n" 2>/dev/null || true
	which tuigreet >/dev/null 2>&1 && echo "[pi] tuigreet is installed" || echo "[pi] WARN: tuigreet not found"
	which niri >/dev/null 2>&1 && echo "[pi] niri present" || true

logs-layer2:
	journalctl -u $(unit_l2) -b --no-pager --no-hostname

logs-layer2\.5:
	journalctl -u $(unit_l25) -b --no-pager --no-hostname

rerun-layer2-install:
	@set -euo pipefail
	echo "[pi] clearing stamp + starting $(unit_l2)"
	rm -f $(stamp_dir)/.layer2-installed || true
	systemctl reset-failed $(unit_l2) || true
	systemctl start $(unit_l2) || true
	systemctl status $(unit_l2) --no-pager || true

rerun-layer2\.5-install:
	@set -euo pipefail
	echo "[pi] clearing stamp + starting $(unit_l25)"
	rm -f $(stamp_dir)/.layer2.5-greetd-installed || true
	systemctl reset-failed $(unit_l25) || true
	systemctl start $(unit_l25) || true
	systemctl status $(unit_l25) --no-pager || true
