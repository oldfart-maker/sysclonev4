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

# -------- Convenience --------
seed-all:  ## Disable firstboot, seed layer1, install oneshot (by-label if ROOT_PART/BOOT_PART exported)
	./tools/seed-disable-firstboot.sh
	./tools/seed-layer1-auto.sh
	./tools/seed-first-boot-service.sh

.PHONY: seed-all

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

seed-layer2-wayland: ## Wayland/wlroots core + pipewire stack + portal
	ROOT_MNT="$(ROOT_MNT)" bash seeds/layer2/seed-wayland.sh

seed-layer2-sway: ## Sway + minimal config + start-sway wrapper
	ROOT_MNT="$(ROOT_MNT)" bash seeds/layer2/seed-sway.sh

seed-layer2-all: seed-layer2-wayland seed-layer2-sway ## Layer 2 full (without DM)

seed-layer2.5-greetd: ## (Optional) greetd + tuigreet (login screen)
	ROOT_MNT="$(ROOT_MNT)" bash seeds/layer2.5/seed-greetd.sh

# ---------------- End Layer 2 block ----------------
