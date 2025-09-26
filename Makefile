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
WIFI_SSID  ?=
WIFI_PASS  ?=
export WIFI_SSID
export WIFI_PASS

IMG_XZ  := $(CACHE_DIR)/$(notdir $(IMG_URL))
IMG_RAW := $(IMG_XZ:.xz=)

DEVICE     ?=
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
	@echo "DEVICE     = $(DEVICE)"
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
	@[ -n "$(DEVICE)" ] || { echo "Refusing: set DEVICE=/dev/sdX"; exit 2; }
	@sudo dd if="$(IMG_RAW)" of="$(DEVICE)" bs=4M status=progress conv=fsync

flash-all: img-unpack sd-write  ## img-download + img-unpack + sd-write

# -------- Seeding --------
seed-layer1:  ## Auto-mount, seed, unmount (uses WIFI_* from Makefile)
	@./tools/seed-layer1-auto.sh

seed-first-boot-service:  ## Seed first-boot systemd service into ROOT and enable (runs once)
	@./tools/seed-first-boot-service.sh

seed-disable-firstboot:  ## Disable Manjaro/OEM first-boot wizard on ROOT (by-label if exported)
	@./tools/seed-disable-firstboot.sh

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

seed-layer2-all: seed-layer2-wayland seed-layer2-sway ## Layer 2 full (without DM)


# ---------------- End Layer 2 block ----------------

# ---------- Mount helpers for seeding (idempotent) ----------
# Only define ROOT_MNT if not already set elsewhere in your Makefile
ROOT_MNT ?= /mnt/sysclone-root

.PHONY: ensure-mounted ensure-unmounted

ensure-mounted: ## Mount ROOT/BOOT by label if not already mounted
	@set -euo pipefail; \
	ROOT_DEV=$$(blkid -L "$(ROOT_LABEL)" || true); \
	BOOT_DEV=$$(blkid -L "$(BOOT_LABEL)" || true); \
	if [ -z "$$ROOT_DEV" ]; then echo "[ensure-mounted] Missing ROOT_LABEL=$(ROOT_LABEL)" >&2; exit 1; fi; \
	if [ -z "$$BOOT_DEV" ]; then echo "[ensure-mounted] Missing BOOT_LABEL=$(BOOT_LABEL)" >&2; exit 1; fi; \
	sudo mkdir -p "$(ROOT_MNT)"; \
	if ! findmnt -rn -S "$$ROOT_DEV" >/dev/null; then \
	  echo "[ensure-mounted] mount $$ROOT_DEV -> $(ROOT_MNT)"; \
	  sudo mount "$$ROOT_DEV" "$(ROOT_MNT)"; \
	fi; \
	sudo mkdir -p "$(ROOT_MNT)/boot"; \
	if ! findmnt -rn -S "$$BOOT_DEV" >/dev/null; then \
	  echo "[ensure-mounted] mount $$BOOT_DEV -> $(ROOT_MNT)/boot"; \
	  sudo mount "$$BOOT_DEV" "$(ROOT_MNT)/boot"; \
	fi; \
	echo "[ensure-mounted] ROOT=$(ROOT_MNT) BOOT=$(ROOT_MNT)/boot ready"

ensure-unmounted:

	@set -euo pipefail; \
	ROOT_MNT="$(ROOT_MNT)"; \
	BOOT_MNT="$$ROOT_MNT/boot"; \
	echo "[ensure-unmounted] checking $$BOOT_MNT and $$ROOT_MNT"; \
	if findmnt -rn "$$BOOT_MNT" >/dev/null 2>&1; then \
	  echo "[ensure-unmounted] umount $$BOOT_MNT"; sudo umount "$$BOOT_MNT" || true; \
	else echo "[ensure-unmounted] $$BOOT_MNT not mounted; skip"; fi; \
	if findmnt -rn "$$ROOT_MNT" >/dev/null 2>&1; then \
	  echo "[ensure-unmounted] umount $$ROOT_MNT"; sudo umount "$$ROOT_MNT" || true; \
	else echo "[ensure-unmounted] $$ROOT_MNT not mounted; skip"; fi; \
	echo "[ensure-unmounted] done"
# Always clear one-shot stamps so Layer 2/2.5 reruns on next boot
clear-layer-stamps: ## Clear one-shot stamps for Layer 2/2.5
	@set -euo pipefail; \
	STAMP_DIR="$(ROOT_MNT)/var/lib/sysclone"; \
	sudo mkdir -p "$$STAMP_DIR"; \
	sudo rm -f "$$STAMP_DIR/.layer2-installed" \
	          "$$STAMP_DIR/.layer2.5-greetd-installed" \

.PHONY: zap-layer-stamps
zap-layer-stamps: ensure-mounted ## Remove L2 stamps on the mounted rootfs
	@set -e; \
	STAMP_DIR="$(ROOT_MNT)/var/lib/sysclone"; \
	sudo mkdir -p "$$STAMP_DIR"; \
	sudo rm -f "$$STAMP_DIR/.layer2-installed" \
	           "$$STAMP_DIR/.layer2.5-greetd-installed" \
	           "$$STAMP_DIR/.fix-ownership-done" || true; \
	echo "[zap-layer-stamps] removed any stamps under $$STAMP_DIR"

.PHONY: seed-layer2-all-fresh
seed-layer2-all-fresh: ensure-mounted zap-layer-stamps seed-layer2-all ensure-unmounted ## Fresh L2 seed (clears stamps first)
	@true

seed-layer2.5-greetd: ensure-mounted clear-layer-stamps ## (Optional) greetd (agreety/tuigreet) login screen
	sudo env ROOT_MNT="/mnt/sysclone-root" bash seeds/layer2.5/seed-greetd.sh

.PHONY: seed-all

# Unified seeding pipeline:
#  1) disable first-boot wizard
#  2) run Layer 1 auto seed
#  3) install/enable first-boot service
#  4) Layer 2 (Wayland + Sway)
#  5) Layer 2.5 (greetd/tuigreet)
#
# Notes:
#  - We DO NOT zap stamps here (use your existing zap target if you want a fresh boot)
#  - We run scripts only if they exist/executable, so this stays portable
#  - ROOT_MNT is passed through sudo so scripts can write to the mounted card
seed-all: ensure-mounted ## Aggregate: Layer1 + Layer2 + Layer2.5
	@echo "[seed-all] step 1/4: layer1 (disable wizard)"
	$(MAKE) seed-layer1-disable-firstboot
	@echo "[seed-all] step 2/4: layer1 (payload + service)"
	$(MAKE) seed-layer1-auto
	$(MAKE) seed-layer1-service
	@echo "[seed-all] step 3/4: layer2 (Wayland + Sway)"
	$(MAKE) seed-layer2-all
	@echo "[seed-all] step 4/4: layer2.5 (greetd/tuigreet)"
	$(MAKE) seed-layer2.5-greetd
	@echo "[seed-all] done"

# -------------------- Layer 1 (first boot) --------------------
.PHONY: seed-layer1-disable-firstboot seed-layer1-service seed-layer1-auto seed-layer1-all

seed-layer1-disable-firstboot: ensure-mounted ## Layer1: disable any OEM first-boot unit on target
	@echo "[layer1] disable-firstboot"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-disable-firstboot.sh

seed-layer1-service: ensure-mounted ## Layer1: install/enable our first-boot service on target
	@echo "[layer1] seed-first-boot-service"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-first-boot-service.sh

seed-layer1-auto: ensure-mounted ## Layer1: place first-boot scripts/payloads
	@echo "[layer1] layer1-auto"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-layer1-auto.sh

seed-layer1-all: ensure-mounted clear-layer1-stamps ensure-mounted clear-layer1-stamps seed-layer1-disable-firstboot seed-layer1-service seed-layer1-auto ## Layer1: all steps
	@echo "[layer1] done"
# --------------------------------------------------------------

clear-layer1-stamps:

	@set -euo pipefail; \
	STAMP_DIR="$(ROOT_MNT)/var/lib/sysclone"; \
	echo "[clear-layer1-stamps] at $$STAMP_DIR"; \
	sudo mkdir -p "$$STAMP_DIR"; \
	sudo rm -f \
	  "$$STAMP_DIR/.layer1-installed" \
	  "$$STAMP_DIR/.first-boot-seeded" \
	  "$$STAMP_DIR/.first-boot-installed" \
	  "$$STAMP_DIR/.layer1"* 2>/dev/null || true; \
	ls -l "$$STAMP_DIR" || true; \
	echo "[clear-layer1-stamps] done"
clear-all-stamps:

	@set -euo pipefail; \
	STAMP_DIR="$(ROOT_MNT)/var/lib/sysclone"; \
	echo "[clear-all-stamps] at $$STAMP_DIR"; \
	sudo mkdir -p "$$STAMP_DIR"; \
	sudo rm -f "$$STAMP_DIR"/.layer*-installed "$$STAMP_DIR"/.first-boot* 2>/dev/null || true; \
	ls -l "$$STAMP_DIR" || true; \
	echo "[clear-all-stamps] done"
