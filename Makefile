# sysclonev4 — Makefile (v0.1.3 clean reset)
SHELL := /bin/bash
.ONESHELL:
.DELETE_ON_ERROR:
.SUFFIXES:

# -------- Config --------
IMG_URL    ?= https://github.com/manjaro-arm/rpi4-images/releases/download/20250915/Manjaro-ARM-minimal-rpi4-20250915.img.xz
CACHE_DIR  ?= cache

# ----- Partition labels (distro defaults; override only if image changes) -----
BOOT_LABEL ?= BOOT_MNJRO
ROOT_LABEL ?= ROOT_MNJRO
export BOOT_LABEL
export ROOT_LABEL

# ----- Wi-Fi (edit once here; inherited by seeding scripts) -----
WIFI_SSID  ?=Hangout
WIFI_PASS  ?=gulfshores
export WIFI_SSID
export WIFI_PASS

# -------- Mount config (sysclonev4 helpers) --------
ROOT_MNT ?= /mnt/sysclone-root
BOOT_MNT ?= /mnt/sysclone-boot

export ROOT_MNT BOOT_MNT DEVICE

# Optional: convenience to "remember" a device once
set-device: ## Set/remember DEVICE=/dev/sdX for later runs (aggregates included)
	@[ -n "$(DEVICE)" ] || { echo "Set DEVICE=/dev/SDX, e.g. make DEVICE=/dev/sdu set-device"; exit 2; }
	@mkdir -p .cache/sysclonev4
	@echo "$(DEVICE)" > .cache/sysclonev4/last-device
	@echo "Saved DEVICE = $(DEVICE)"

IMG_XZ  := $(CACHE_DIR)/$(notdir $(IMG_URL))
IMG_RAW := $(IMG_XZ:.xz=)

# Resolve DEVICE from cache if empty (works even if exported empty)
DEVICE_EFFECTIVE := $(or $(strip $(DEVICE)),$(shell test -f .cache/sysclonev4/last-device && cat .cache/sysclonev4/last-device))

# Resolve DEVICE from cache if empty (works even if exported empty)
DEVICE_EFFECTIVE := $(or $(strip $(DEVICE)),$(shell test -f .cache/sysclonev4/last-device && cat .cache/sysclonev4/last-device))

# Resolve DEVICE from cache if empty (works even if exported empty)
DEVICE := $(or $(strip $(DEVICE)),$(shell test -f .cache/sysclonev4/last-device && cat .cache/sysclonev4/last-device))


BOOT_MOUNT ?= /run/media/$(USER)/BOOT
CONFIRM    ?=

# -------- Help --------
# List any "target: ## description" (auto-discovered)
help:  ## Show available targets + param hints (use: make help TARGET=name)
	@python3 tools/mkhelp.py $(firstword $(MAKEFILE_LIST)) "$(TARGET)"
# -------- Introspection --------
show-config:  ## Show important variables
	@echo "IMG_URL    = $(IMG_URL)"
	@echo "CACHE_DIR  = $(CACHE_DIR)"
	@echo "IMG_XZ     = $(IMG_XZ)"
	@echo "IMG_RAW    = $(IMG_RAW)"
	@echo "DEVICE     = $(DEVICE_EFFECTIVE)"
	@echo "BOOT_MOUNT = $(BOOT_MOUNT)"
	@echo "BOOT_LABEL = $(BOOT_LABEL)"
	@echo "ROOT_LABEL = $(ROOT_LABEL)"
	@echo "WIFI_SSID  = $(WIFI_SSID)"
	@echo "WIFI_PASS  = $(if $(strip $(WIFI_PASS)),(set),(unset))"
# -------- Image workflow --------
img-download:  ## Download the image (.xz) into cache/
	@mkdir -p $(CACHE_DIR)
	@if [ ! -f "$(IMG_XZ)" ]; then \
	  echo "[dl] $(IMG_URL) -> $(IMG_XZ)"; \
	  curl -fL --progress-bar "$(IMG_URL)" -o "$(IMG_XZ)"; \
	else echo "[dl] cached: $(IMG_XZ)"; fi

img-unpack: img-download  ## Decompress .xz into a raw .img (once)
	@if [ ! -f "$(IMG_RAW)" ]; then \
	  echo "[xz] unpack -> $(IMG_RAW)"; \
	  xz -dkc "$(IMG_XZ)" > "$(IMG_RAW)"; \
	else echo "[xz] cached: $(IMG_RAW)"; fi

sd-write:  ## Write raw image to SD (DESTRUCTIVE) — pass DEVICE=/dev/sdX CONFIRM=yes
	@[ "$(CONFIRM)" = "yes" ] || { echo "Refusing: set CONFIRM=yes"; exit 2; }
	@[ -n "$(DEVICE_EFFECTIVE)" ] || { echo "Refusing: set DEVICE=/dev/sdX (or use make DEVICE=/dev/sdX set-device)"; exit 2; }
	@sudo dd if="$(IMG_RAW)" of="$(DEVICE_EFFECTIVE)" bs=4M status=progress conv=fsync

flash-all: img-unpack sd-write  ## img-download + img-unpack + sd-write

# Convenience: unpack + write + offline expand (re-uses existing targets/vars)
flash-all+expand: img-unpack sd-write img-expand-rootfs-offline  ## unpack, write, expand (offline)


# -------- Versioning --------
tag:  ## Create annotated git tag: make tag VERSION=vX.Y.Z
	@[ -n "$(VERSION)" ] || { echo "Set VERSION=vX.Y.Z"; exit 2; }
	@git tag -a "$(VERSION)" -m "$(VERSION)"

version-bump:  ## Write VERSION file + commit: make version-bump VERSION=vX.Y.Z
	@[ -n "$(VERSION)" ] || { echo "Set VERSION=vX.Y.Z"; exit 2; }
	@echo "$(VERSION)" > VERSION
	@git add VERSION
	@git commit -m "$(VERSION): bump VERSION file"

.PHONY: help show-config img-download img-unpack sd-write flash-all \
        seed-layer1 seed-first-boot-service seed-disable-firstboot \
        tag version-bump

tidy:  ## Remove local backup files (.bak.*) from tools/ and seeds/
	@rm -f tools/*.bak* 2>/dev/null || true
	@find seeds -type f -name '*.bak.*' -delete 2>/dev/null || true
	@echo "[tidy] done"
.PHONY: tidy

# ---------------- Layer 2: Wayland + Sway (test WM) ----------------
.PHONY: seed-layer2-wayland seed-layer2-sway seed-layer2-all seed-layer2.5-greetd

# These targets seed Wayland/wlroots tools and Sway into the target rootfs
# mounted at ROOT_MNT (same convention as Layer 1). They are host-side only.
#
# Usage example:
#   make seed-layer2-all ROOT_MNT=/mnt/sysclone-root
#
# Layer 2.5 (optional now): greetd + tuigreet (login screen)
# Add only when you want a DM on boot instead of TTY 'start-sway'.

seed-layer2-wayland: ensure-mounted ## Wayland/wlroots core + pipewire stack + portal
	bash seeds/layer2/seed-wayland.sh

seed-layer2-sway: ensure-mounted ## Sway + minimal config + start-sway wrapper
	bash seeds/layer2/seed-sway.sh
# ---------------- End Layer 2 block ----------------

# ---------------- Layer 2.5: (DM) ----------------
seed-layer2.5-greetd: ensure-mounted  ## (Optional) greetd (agreety/tuigreet) login screen
	sudo env ROOT_MNT="/mnt/sysclone-root" bash seeds/layer2.5/seed-greetd.sh
# ---------------- End Layer 2 block ----------------


# -------------------- Layer 1 (first boot) --------------------
.PHONY: seed-layer1-disable-first-boot seed-layer1-first-boot-service

seed-layer1-disable-first-boot: ensure-mounted ## Layer1: disable any OEM first-boot unit on target
	@echo "[layer1] disable-firstboot"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-disable-firstboot.sh

seed-layer1-first-boot-service: ensure-mounted ## Layer1: install/enable our first-boot service on target
	@echo "[layer1] seed-first-boot-service"
	sudo env ROOT_MNT="$(ROOT_MNT)" sudo env ROOT_MNT="$(ROOT_MNT)" WIFI_SSID="$(WIFI_SSID)" WIFI_PASS="$(WIFI_PASS)" USERNAME="$(USERNAME)" USERPASS="$(USERPASS)" bash tools/seed-first-boot-service.sh

.PHONY: clear-layer1-stamps clear-layer2-stamps clear-all-stamps

## Clear Layer 1 first-boot stamps in $(ROOT_MNT)
clear-layer1-stamps: ## Clear Layer 1 first-boot stamps in $(ROOT_MNT)
	@echo "[clear-layer1-stamps] at $(ROOT_MNT)/var/lib/sysclone"
	@sudo rm -f "$(ROOT_MNT)/var/lib/sysclone/first-boot.done" \
	            "$(ROOT_MNT)/var/lib/sysclone/manjaro-firstboot-disabled" 2>/dev/null || true
	@echo "[clear-layer1-stamps] done"

clear-layer2-stamps: ## Clear Layer 2 stamps in $(ROOT_MNT)
	@echo "[clear-layer2-stamps] at $(ROOT_MNT)/var/lib/sysclone"
	@sudo rm -rf "$(ROOT_MNT)/var/lib/sysclone/layer2" 2>/dev/null || true
	@sudo find "$(ROOT_MNT)/var/lib/sysclone" -maxdepth 1 -type f -name 'layer2*.stamp' -exec rm -f {} + 2>/dev/null || true
	@echo "[clear-layer2-stamps] done"

clear-all-stamps: clear-layer1-stamps clear-layer2-stamps ## Clear all sysclone stamps in $(ROOT_MNT)

# ---- Check the status of layer stamps ---
.PHONY: check-stamps show-stamps

show-stamps: ensure-mounted ## List all stamp files under ROOT_MNT/var/lib/sysclone
	@DIR="$(ROOT_MNT)/var/lib/sysclone"; \
	if [ -d "$$DIR" ]; then \
	  echo "[stamps] listing $$DIR"; \
	  sudo ls -la "$$DIR"; \
	else \
	  echo "[stamps] directory missing: $$DIR"; \
	fi

# ---------------- Layer 2.5 maintenance ----------------
clear-layer2.5-stamps: ensure-mounted ## Clear L2.5 greetd stamp on target rootfs
	@echo "[clear:l2.5] removing greetd stamp"
	sudo rm -f $(ROOT_MNT)/var/lib/sysclone/.layer2.5-greetd-installed

# ---------------- Layer 1: aggregate ----------------
seed-layer1-all: ensure-mounted ## Layer1: disable first-boot + install first-boot service; leaves card unmounted
	@set -euo pipefail; \
	  $(MAKE) clear-layer1-stamps; \
	  $(MAKE) seed-layer1-disable-first-boot; \
	  $(MAKE) seed-layer1-expand-rootfs; \
	  $(MAKE) seed-layer1-net-bootstrap; \
	  $(MAKE) seed-layer1-first-boot-service; \
	  $(MAKE) seed-pi-devtools; \
	  $(MAKE) ensure-unmounted; \
	  echo "[layer1] aggregate done"

.PHONY: seed-layer1-all

# ---------------- Layer 2: aggregate ----------------
seed-layer2-all: ensure-mounted ## Layer2: wayland providers + sway; leaves card unmounted
	@set -euo pipefail; \
	  $(MAKE) clear-layer2-stamps; \
	  $(MAKE) seed-layer2-wayland; \
	  $(MAKE) seed-layer2-sway; \
	  $(MAKE) ensure-unmounted; \
	  echo "[layer2] aggregate done"

.PHONY: seed-layer2-all

# ---------------- Layer 2.5: aggregate ----------------
seed-layer2.5-all: ensure-mounted ## Layer2.5: greetd/tuigreet; leaves card unmounted
	@set -euo pipefail; \
	  $(MAKE) clear-layer2.5-stamps; \
	  $(MAKE) seed-layer2.5-greetd; \
	  $(MAKE) ensure-unmounted; \
	  echo "[layer2.5] aggregate done"

.PHONY: seed-layer2.5-all

# ---------------- Pi devtools (on-target helpers) ----------------
seed-pi-devtools: ensure-mounted ## Install Pi debugging helpers (scpi + pi.mk)
	@set -euo pipefail
	@sudo install -D -m 0644 tools/payloads/usr-local-share/sysclone-pi.mk "$(ROOT_MNT)/usr/local/share/sysclone/pi.mk"
	@sudo install -D -m 0755 tools/payloads/usr-local-bin/scpi "$(ROOT_MNT)/usr/local/bin/scpi"
	@echo "[pi-devtools] installed: /usr/local/share/sysclone/pi.mk and /usr/local/bin/scpi"
	@$(MAKE) ensure-unmounted
.PHONY: seed-pi-devtools

# Layer1: stage rootfs expansion for first boot (uses helper if present)
seed-layer1-expand-rootfs: ensure-mounted ## Layer1: stage rootfs grow on first boot
	@set -euo pipefail; \
	  if [ -x tools/seed-expand-rootfs.sh ]; then \
	    echo "[layer1] expand-rootfs via tools/seed-expand-rootfs.sh"; \
	    sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-expand-rootfs.sh; \
	  else \
	    echo "[layer1] WARN: tools/seed-expand-rootfs.sh not found; skipping expansion staging"; \
	  fi

.PHONY: seed-layer1-expand-rootfs

# Show boot/service progress on console + write logs to /boot/sysclone-status/
seed-boot-visibility: ensure-mounted ## Add console output & BOOT logs for first-boot/L2/L2.5
	@set -euo pipefail; \
	  sudo env ROOT_MNT="$(ROOT_MNT)" BOOT_MNT="$(BOOT_MNT)" bash tools/seed-boot-visibility.sh; \
	  $(MAKE) ensure-unmounted; \
	  echo "[boot-visibility] done"
.PHONY: seed-boot-visibility


# Layer1: bootstrap clock/certs/keyrings/mirrors on first boot (pre-firstboot)
seed-layer1-network-bootstrap: ensure-mounted ## Layer1: stage network/certs bootstrap service
	@echo "[layer1] seed-network-bootstrap"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-layer1-network-bootstrap.sh

.PHONY: seed-layer1-network-bootstrap

# Layer1: stage network/clock/mirrors bootstrap (runs once on target)
seed-layer1-net-bootstrap: ensure-mounted  ## Layer1: seed net/clock/certs bootstrap (on-target)
	@echo "[layer1] net-bootstrap via tools/seed-net-bootstrap.sh"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-net-bootstrap.sh

## Stable mount/unmount by LABEL (no /dev/sdX guessing)
.PHONY: ensure-mounted ensure-unmounted resolve-disk

ensure-mounted:
	@echo "[make] mounting $(ROOT_LABEL) -> $(ROOT_MNT) and $(BOOT_LABEL) -> $(BOOT_MNT)"
	@BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)" ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-mounted

ensure-unmounted:
	@echo "[make] unmounting $(ROOT_MNT) and $(BOOT_MNT) (by label)"
	@BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)" ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-unmounted

# Optional: print the parent disk (e.g. /dev/sdc) resolved from labels/mounts
resolve-disk:
	@BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)" ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh resolve-disk

# ---------- devices quick smoke test ----------
.PHONY: devices-smoke
devices-smoke:
	@echo "[smoke] unmount (quiet)"; \
	  BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)"   ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-unmounted; \
	echo "[smoke] mount"; \
	  BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)"   ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-mounted; \
	echo "[smoke] verify"; \
	  findmnt -nr -o SOURCE,TARGET | grep -E "(/mnt/sysclone-(boot|root))" || true; \
	echo "[smoke] unmount (final)"; \
	  BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)"   ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh ensure-unmounted


# --- override: expand rootfs offline with disk auto-resolve via labels (robust) ---
.PHONY: img-expand-rootfs-offline
img-expand-rootfs-offline:
	@echo "[make] offline expand (auto-resolve by label: $(ROOT_LABEL)/$(BOOT_LABEL))"
	@set -euo pipefail; \
	ROOTVAL="$(ROOT_LABEL)"; BOOTVAL="$(BOOT_LABEL)"; \
	get_disk() { \
	  BOOT_LABEL="$(BOOT_LABEL)" ROOT_LABEL="$(ROOT_LABEL)" \
	  BOOT_MOUNT="$(BOOT_MNT)" ROOT_MOUNT="$(ROOT_MNT)" \
	  SUDO="$(SUDO)" bash tools/devices.sh resolve-disk | \
	  awk -v r="^"$$ROOTVAL" ->" -v b="^"$$BOOTVAL" ->" '\
	    $0 ~ r { if (match($0, /\(disk: ([^)]+)\)/, m)) { print m[1]; exit } } \
	    $0 ~ b { if (match($0, /\(disk: ([^)]+)\)/, m)) { print m[1]; exit } }'; \
	}; \
	DISK=""; \
	for i in $$(seq 1 120); do \
	  DISK="$$(get_disk)"; \
	  if [ -n "$$DISK" ] && [ -b "$$DISK" ]; then break; fi; \
	  sleep 0.5; \
	done; \
	# Fallback to $(DEVICE) if still unresolved and valid
	if [ -z "$$DISK" ] || [ ! -b "$$DISK" ]; then \
	  if [ -n "$(DEVICE)" ] && [ -b "$(DEVICE)" ]; then DISK="$(DEVICE)"; fi; \
	fi; \
	if [ -z "$$DISK" ] || [ ! -b "$$DISK" ]; then \
	  echo "[host-expand] ERROR: could not resolve SD disk by label or $(DEVICE)"; exit 1; \
	fi; \
	echo "[make] expanding on $$DISK"; \
	sfx=""; case "$$DISK" in *mmcblk*|*nvme*) sfx="p";; esac; \
	ROOT_PART="$$DISK$${sfx}2"; \
	partprobe "$$DISK" || true; sync; \
	parted -s "$$DISK" unit % print >/dev/null; \
	parted -s "$$DISK" -- resizepart 2 100%; \
	partprobe "$$DISK" || true; sync; \
	e2fsck -fp "$$ROOT_PART" || true; \
	resize2fs "$$ROOT_PART"; \
	echo "[make] expand done"
