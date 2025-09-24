# sysclonev4 — Makefile (v0.0.37)
SHELL := /bin/bash
.ONESHELL:
.DELETE_ON_ERROR:
.SUFFIXES:

# ---------- Config ----------
IMG_URL    ?= https://github.com/manjaro-arm/rpi4-images/releases/download/20250915/Manjaro-ARM-minimal-rpi4-20250915.img.xz
CACHE_DIR  ?= cache
IMG_XZ     := $(CACHE_DIR)/$(notdir $(IMG_URL))
IMG_RAW    := $(IMG_XZ:.img.xz=.img)
DEVICE     ?=
BOOT_MOUNT ?= /run/media/$(USER)/BOOT
CONFIRM    ?=

# ---------- Help ----------
# List any "target:  ## description"
help: ## Show available targets (auto-discovered)
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*##' $(MAKEFILE_LIST) | sort | sed -E 's/^([a-zA-Z0-9_.-]+):.*## (.*)$$/  \1 - \2/'

# ---------- Utility ----------
show-config: ## Show important variables
	@echo "IMG_URL    = $(IMG_URL)"
	@echo "CACHE_DIR  = $(CACHE_DIR)"
	@echo "IMG_XZ     = $(IMG_XZ)"
	@echo "IMG_RAW    = $(IMG_RAW)"
	@echo "DEVICE     = $(DEVICE)"
	@echo "BOOT_MOUNT = $(BOOT_MOUNT)"
	@echo "CONFIRM    = $(CONFIRM)"

# ---------- Image prep ----------
$(CACHE_DIR):
	mkdir -p $(CACHE_DIR)

img-download: $(CACHE_DIR) ## Download the image (.xz) into cache/
	curl -fL --retry 3 -o "$(IMG_XZ).partial" "$(IMG_URL)"
	mv -f "$(IMG_XZ).partial" "$(IMG_XZ)"
	@echo "[img] downloaded: $(IMG_XZ)"

img-unpack: $(IMG_RAW) ## Decompress .xz into a raw .img (once)

$(IMG_RAW): $(IMG_XZ)
	@if [[ -f "$(IMG_RAW)" ]]; then \
	  echo "[img] already exists: $(IMG_RAW)"; \
	else \
	  echo "[img] decompressing: $(IMG_XZ) -> $(IMG_RAW)"; \
	  xz -dc "$(IMG_XZ)" > "$(IMG_RAW).partial"; \
	  mv -f "$(IMG_RAW).partial" "$(IMG_RAW)"; \
	  sync; \
	fi

# ---------- Write SD (DESTRUCTIVE) ----------
sd-write: ## Write raw image to SD (DESTRUCTIVE) — pass DEVICE=/dev/sdX CONFIRM=yes
	@if [[ -z "$(DEVICE)" ]]; then echo "ERROR: set DEVICE=/dev/sdX (or /dev/mmcblk0)"; exit 1; fi
	@if [[ "$(CONFIRM)" != "yes" ]]; then echo "ERROR: set CONFIRM=yes to proceed (DESTRUCTIVE)"; exit 1; fi
	@if [[ ! -b "$(DEVICE)" ]]; then echo "ERROR: DEVICE is not a block device: $(DEVICE)"; exit 1; fi
	@if [[ ! -f "$(IMG_RAW)" ]]; then $(MAKE) img-unpack; fi
	@echo "[dd] writing $(IMG_RAW) -> $(DEVICE)"
	sudo umount $(DEVICE)* 2>/dev/null || true
	sudo dd if="$(IMG_RAW)" of="$(DEVICE)" bs=4M status=progress conv=fsync
	sync
	@echo "[dd] done"

# ---------- Seeding ----------
seed-layer1: ## Auto-mount, seed, unmount (WIFI_SSID=.. WIFI_PASS=.. optional)
	./tools/seed-layer1-auto.sh

seed-first-boot-service: ## Seed first-boot systemd service into ROOT and enable (runs once on first boot)
	./tools/seed-first-boot-service.sh

# Back-compat alias (for now)
install-first-boot-unit: ## (deprecated) use 'seed-first-boot-service'
	@echo "[note] 'install-first-boot-unit' is deprecated; use 'seed-first-boot-service'"
	$(MAKE) seed-first-boot-service

# ---------- One-shot convenience ----------
flash-all: ## img-download + img-unpack + sd-write (requires DEVICE=/dev/sdX CONFIRM=yes)
	$(MAKE) img-download
	$(MAKE) img-unpack
	$(MAKE) sd-write

# ---------- Versioning ----------
tag: ## Create annotated git tag — pass VERSION=vX.Y.Z
	@if [[ -z "$(VERSION)" ]]; then echo "usage: make tag VERSION=vX.Y.Z"; exit 1; fi
	git tag -a "$(VERSION)" -m "$(VERSION)"
	@echo "tagged: $(VERSION)"

version-bump: ## Write VERSION file + commit — pass VERSION=vX.Y.Z
	@if [[ -z "$(VERSION)" ]]; then echo "usage: make version-bump VERSION=vX.Y.Z"; exit 1; fi
	printf '%s\n' "$(VERSION)" > VERSION
	git add VERSION
	git commit -m "$(VERSION): bump VERSION file"

.PHONY: help show-config img-download img-unpack sd-write seed-layer1 seed-first-boot-service install-first-boot-unit flash-all tag version-bump
