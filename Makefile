# Makefile — sysclonev4 (clean, with hard TABs)
SHELL := /bin/bash

# Defaults (override as needed)
IMG_URL ?= https://github.com/manjaro-arm/rpi4-images/releases/download/20250915/Manjaro-ARM-minimal-rpi4-20250915.img.xz
CACHE_DIR ?= cache
DEVICE ?=
CONFIRM ?=
BOOT_MOUNT := /run/media/username/BOOT

IMG_XZ  := $(CACHE_DIR)/$(notdir $(IMG_URL))
IMG_RAW := $(IMG_XZ:.img.xz=.img)

.PHONY: help show-config img-download img-unpack sd-write seed-layer1 flash-all tag version-bump

show-config:
	@echo "IMG_URL    = $(IMG_URL)"
	@echo "CACHE_DIR  = $(CACHE_DIR)"
	@echo "IMG_XZ     = $(IMG_XZ)"
	@echo "IMG_RAW    = $(IMG_RAW)"
	@echo "DEVICE     = $(DEVICE)"
	@echo "BOOT_MOUNT = $(BOOT_MOUNT)"
	@echo "CONFIRM    = $(CONFIRM)"

img-download:
	@mkdir -p "$(CACHE_DIR)"
	@echo "Downloading image from:"
	@echo "  $(IMG_URL)"
	@echo "-> $(IMG_XZ)"
	@curl -L --fail --retry 3 --continue-at - -o "$(IMG_XZ).part" "$(IMG_URL)"
	@mv -f "$(IMG_XZ).part" "$(IMG_XZ)"
	@echo "Done."

img-unpack: $(IMG_XZ)
	@if [[ ! -f "$(IMG_RAW)" ]]; then \
			echo "Decompressing $(IMG_XZ) -> $(IMG_RAW)"; \
			xz -T0 -dkc -- "$(IMG_XZ)" > "$(IMG_RAW)"; \
			sync; \
		else \
			echo "$(IMG_RAW) already exists; skipping."; \
		fi

sd-write: $(IMG_RAW)
	@if [[ -z "$(DEVICE)" ]]; then echo "ERROR: set DEVICE=/dev/sdX (or /dev/mmcblk0)"; exit 1; fi
	@if [[ "$(CONFIRM)" != "yes" ]]; then echo "ERROR: set CONFIRM=yes to proceed (DESTRUCTIVE)"; exit 1; fi
	@if [[ ! -b "$(DEVICE)" ]]; then echo "ERROR: $(DEVICE) is not a block device"; exit 1; fi
	@echo "About to write $(IMG_RAW) -> $(DEVICE) (this will erase the device)"
	@echo "Writing..."
	@sudo dd if="$(IMG_RAW)" of="$(DEVICE)" bs=4M status=progress conv=fsync
	@echo "Syncing..."; sync
	@echo "Done writing image to $(DEVICE)."
	@echo "Tip: re-plug the SD card so partitions are re-read before seeding."

flash-all: img-download img-unpack sd-write
	@echo "flash-all start"

tag:
	@if [[ -z "$(VERSION)" ]]; then echo "ERROR: set VERSION=vX.Y.Z"; exit 1; fi
	@git tag -a $(VERSION) -m "$(VERSION)"
	@echo "Created tag $(VERSION)"

version-bump:
	@if [[ -z "$(VERSION)" ]]; then echo "ERROR: set VERSION=vX.Y.Z"; exit 1; fi
	@echo "$(VERSION:v%=%)" > VERSION
	@git add VERSION
	@git commit -m "Bump version to $(VERSION)"
	@echo "Version bumped to $(VERSION)"

.PHONY: seed-layer1-auto
seed-layer1-auto:
	./tools/seed-layer1-auto.sh

.PHONY: seed-layer1

.PHONY: seed-layer1
seed-layer1: seed-layer1-auto
	@true


.PHONY: help
help:
	@echo 'Targets:'
	@echo '  show-config                         - Show important variables'
	@echo '  img-download [IMG_URL=...]          - Download the image (.xz) into cache/'
	@echo '  img-unpack                          - Decompress .xz into a raw .img (once)'
	@echo '  sd-write DEVICE=/dev/sdX CONFIRM=yes- Write raw image to SD (DESTRUCTIVE)'
	@echo '  seed-layer1                         - Auto-mount, seed, unmount'
	@echo '  flash-all DEVICE=... CONFIRM=yes    - img-download + img-unpack + sd-write'
	@echo '  tag VERSION=vX.Y.Z                  - Create annotated git tag'
	@echo '  version-bump VERSION=vX.Y.Z         - Write VERSION file + commit'
