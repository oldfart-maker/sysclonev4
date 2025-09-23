#!/usr/bin/env bash
set -euo pipefail

# tools/hardcode-boot-mount-v0.0.2.sh
# Overwrites Makefile with BOOT_MOUNT hardcoded to /run/media/username/BOOT,
# commits, and tags v0.0.2.
# Run from repo root: ./tools/hardcode-boot-mount-v0.0.2.sh

ME=$(basename "$0")
die() { echo "[$ME] ERROR: $*" >&2; exit 1; }

repo_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[[ -n "$repo_root" ]] || die "Not inside a git repo"
cd "$repo_root"

makefile_path="Makefile"
backup="Makefile.bak.$(date +%Y%m%d%H%M%S)"

# New Makefile content embedded here-doc
read -r -d '' NEW_MAKE <<'EOF_MAKE'
# Makefile — sysclonev4 (BOOT_MOUNT hardcoded)
SHELL := /bin/bash

# Defaults (override as needed)
IMG_URL ?= https://github.com/manjaro-arm/rpi4-images/releases/download/20250915/Manjaro-ARM-minimal-rpi4-20250915.img.xz
CACHE_DIR ?= cache
DEVICE ?=
CONFIRM ?=

# Hardcoded BOOT mount to match your workflow
BOOT_MOUNT := /run/media/username/BOOT

IMG_XZ  := $(CACHE_DIR)/$(notdir $(IMG_URL))
IMG_RAW := $(IMG_XZ:.img.xz=.img)

.PHONY: help show-config img-download img-unpack sd-write seed-layer1 flash-all tag version-bump

help:
	@echo 'Targets:'
	@echo '  show-config                         - Show important variables'
	@echo '  img-download [IMG_URL=...]          - Download the image (.xz) into $(CACHE_DIR)/'
	@echo '  img-unpack                          - Decompress .xz into a raw .img (once)'
	@echo '  sd-write DEVICE=/dev/sdX CONFIRM=yes- Write raw image to SD (DESTRUCTIVE)'
	@echo '  seed-layer1                         - Copy first-boot script to BOOT (vfat): $(BOOT_MOUNT)'
	@echo '  flash-all DEVICE=... CONFIRM=yes    - img-download + img-unpack + sd-write'
	@echo '  tag VERSION=vX.Y.Z                  - Create annotated git tag'
	@echo '  version-bump VERSION=vX.Y.Z         - Write VERSION file + commit'

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

seed-layer1:
	@if [[ ! -d "$(BOOT_MOUNT)" ]]; then echo "ERROR: BOOT_MOUNT does not exist: $(BOOT_MOUNT)"; exit 1; fi
	@echo "Seeding Layer 1 to $(BOOT_MOUNT)..."
	@install -Dm644 seeds/layer1/first-boot.sh "$(BOOT_MOUNT)/sysclone-first-boot.sh"
	@{ \
		echo "SysClone v4 Layer1 seed"; \
		echo "On the Pi (after first boot):"; \
		echo "  sudo install -Dm755 /boot/sysclone-first-boot.sh /usr/local/sbin/sysclone-first-boot.sh"; \
		echo "  sudo /usr/local/sbin/sysclone-first-boot.sh"; \
	} > "$(BOOT_MOUNT)/README-sysclone.txt"
	@echo "Seed complete."

flash-all: img-download img-unpack sd-write
	@echo "flash-all complete. Now run: make seed-layer1"

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

EOF_MAKE

echo "[$ME] Backing up existing Makefile -> $backup"
[[ -f "$makefile_path" ]] && cp -f "$makefile_path" "$backup" || true

echo "[$ME] Writing hardcoded BOOT_MOUNT Makefile"
printf "%s\n" "$NEW_MAKE" > "$makefile_path"

echo "[$ME] Staging & committing"
git add Makefile
git commit -m "v0.0.2: Makefile hardcodes BOOT_MOUNT to /run/media/username/BOOT; seed-layer1 simplified" || {
  echo "[$ME] Nothing to commit (possibly unchanged)."
}

if git rev-parse -q --verify "v0.0.2" >/dev/null; then
  echo "[$ME] Tag v0.0.2 already exists; skipping."
else
  git tag -a v0.0.2 -m "v0.0.2 Makefile: BOOT_MOUNT hardcoded"
  echo "[$ME] Created tag v0.0.2"
fi

echo "[$ME] Done."
