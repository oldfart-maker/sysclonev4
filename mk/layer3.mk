.PHONY: clear-layer3-stamps seed-layer3-home seed-layer3-vendor-hm seed-layer3-vendor-nixpkgs seed-layer3-all set-hm-user

# Stable user for Home Manager on the target (override per-call: HM_USER=mike make …)
HM_USER ?= username-aarch64

## Layer 3 (Home Manager on Arch target)
clear-layer3-stamps: ensure-mounted ## Clear L3 stamp on target rootfs
	@echo "[clear:l3] removing home-manager stamp"
	sudo rm -f $(ROOT_MNT)/var/lib/sysclone/.layer3-home-done || true

seed-layer3-home: ensure-mounted ## Stage Nix + Home Manager oneshot on target
	@echo "[layer3] seeding nix + home-manager oneshot"
	sudo env ROOT_MNT="$(ROOT_MNT)" USERNAME="$(HM_USER)" HM_USER="$(HM_USER)" bash seeds/layer3/seed-home.sh

seed-layer3-vendor-hm: ## Vendor Home Manager (offline-friendly)
	@set -euo pipefail; \
	mkdir -p seeds/layer3/vendor; \
	if [ ! -d seeds/layer3/vendor/home-manager/.git ]; then \
	  echo "[layer3] cloning home-manager (shallow)"; \
	  git clone --depth=1 https://github.com/nix-community/home-manager seeds/layer3/vendor/home-manager; \
	else \
	  echo "[layer3] updating vendor/home-manager"; \
	  git -C seeds/layer3/vendor/home-manager fetch --depth=1 origin; \
	  git -C seeds/layer3/vendor/home-manager reset --hard origin/HEAD; \
	fi; \
	echo "[layer3] vendor/home-manager @ $$(git -C seeds/layer3/vendor/home-manager rev-parse --short HEAD)"

seed-layer3-vendor-nixpkgs: ## Vendor nixpkgs (offline-friendly)
	@set -euo pipefail; \
	mkdir -p seeds/layer3/vendor; \
	if [ ! -d seeds/layer3/vendor/nixpkgs/.git ]; then \
	  echo "[layer3] cloning nixpkgs (shallow, nixos-24.05)"; \
	  git clone --depth=1 --branch nixos-24.05 https://github.com/NixOS/nixpkgs seeds/layer3/vendor/nixpkgs; \
	else \
	  echo "[layer3] updating vendor/nixpkgs (nixos-24.05)"; \
	  git -C seeds/layer3/vendor/nixpkgs fetch --depth=1 origin nixos-24.05; \
	  git -C seeds/layer3/vendor/nixpkgs checkout -q nixos-24.05; \
	  git -C seeds/layer3/vendor/nixpkgs reset --hard origin/nixos-24.05; \
	fi; \
	echo "[layer3] vendor/nixpkgs @ $$(git -C seeds/layer3/vendor/nixpkgs rev-parse --short HEAD)"

seed-layer3-all: ensure-mounted ## Aggregate: clear stamp, vendor HM+nixpkgs, seed oneshot, unmount
	@set -euo pipefail; \
	  $(MAKE) clear-layer3-stamps; \
	  $(MAKE) seed-layer3-vendor-nixpkgs; \
	  $(MAKE) seed-layer3-vendor-hm; \
	  $(MAKE) seed-layer3-home; \
	  $(MAKE) ensure-unmounted; \
	  echo "[layer3] aggregate done"

# Persist a new HM user into the root Makefile (stable-var pattern).
set-hm-user: ## Usage: make set-hm-user HM_USER=mike
	@set -euo pipefail; \
	test -n "$(HM_USER)"; \
	if grep -qE '^[[:space:]]*HM_USER[[:space:]]*=.*' Makefile; then \
	  tmp=$$(mktemp); \
	  sed -E 's|^[[:space:]]*HM_USER[[:space:]]*=.*|HM_USER = $(HM_USER)|' Makefile > $$tmp; \
	  mv $$tmp Makefile; \
	  echo "[set-hm-user] HM_USER set to '$(HM_USER)' in Makefile"; \
	else \
	  echo 'HM_USER = $(HM_USER)' >> Makefile; \
	  echo "[set-hm-user] HM_USER appended to Makefile"; \
	fi
