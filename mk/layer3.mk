.PHONY: clear-layer3-stamps seed-layer3-home seed-layer3-all set-hm-user

# Stable user for Home Manager on the target (override per-call: HM_USER=mike make …)
HM_USER ?= username

## Layer 3 (Home Manager on Arch target)
clear-layer3-stamps: ensure-mounted ## Clear L3 stamp on target rootfs
	@echo "[clear:l3] removing home-manager stamp"
	sudo rm -f $(ROOT_MNT)/var/lib/sysclone/.layer3-home-done || true

seed-layer3-home: ensure-mounted ## Stage Nix + Home Manager oneshot on target
	@echo "[layer3] seeding nix + home-manager oneshot"
	sudo env ROOT_MNT="$(ROOT_MNT)" USERNAME="$(HM_USER)" bash seeds/layer3/seed-home.sh

seed-layer3-all: ensure-mounted ## Stage HM and unmount
	@set -euo pipefail; \
	  $(MAKE) clear-layer3-stamps; \
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

.PHONY: validate-layer3
validate-layer3: ## Validate Layer3 seed content & patterns
	@bash tools/validate-layer3.sh

.PHONY: validate-layer3
validate-layer3:
	@echo "[validate-layer3] disabled"
