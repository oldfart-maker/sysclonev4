#!/usr/bin/env bash
set -Eeuo pipefail
mf="Makefile"
[[ -f "$mf" ]] || { echo "[patch] ERROR: Makefile not found"; exit 1; }

tmp="$(mktemp)"
awk -v TGT="img-expand-rootfs-offline:" '
  BEGIN{
    in=0
  }
  {
    if ($0 == TGT) {
      # Start of the target to replace: print header (the target line) then inject new recipe
      print $0
      in=1
      print "\t@echo \"[make] offline expand (auto-resolve by label: $(ROOT_LABEL)/$(BOOT_LABEL))\""
      print "\t@set -euo pipefail; \\"
      print "\tROOTVAL=\"$(ROOT_LABEL)\"; BOOTVAL=\"$(BOOT_LABEL)\"; \\"
      print "\tresolve_once() { \\"
      print "\t  BOOT_LABEL=\"$(BOOT_LABEL)\" ROOT_LABEL=\"$(ROOT_LABEL)\" \\"
      print "\t  BOOT_MOUNT=\"$(BOOT_MNT)\" ROOT_MOUNT=\"$(ROOT_MNT)\" \\"
      print "\t  SUDO=\"$(SUDO)\" bash tools/devices.sh resolve-disk; \\"
      print "\t}; \\"
      print "\tDISK=\"\"; \\"
      print "\tfor i in $$(seq 1 120); do \\"
      print "\t  out=\"$$(resolve_once || true)\"; \\"
      print "\t  line=\"$$(printf '%s\\n' \"$$out\" | grep -E \"^($$ROOTVAL|$$BOOTVAL)[[:space:]]->\" | head -n1 || true)\"; \\"
      print "\t  if [ -n \"$$line\" ]; then \\"
      print "\t    d=\"$$(sed -n 's/.*(disk: \\([^)]*\\)).*/\\1/p' <<<\"$$line\")\"; \\"
      print "\t    if [ -n \"$$d\" ] && [ -b \"$$d\" ]; then DISK=\"$$d\"; break; fi; \\"
      print "\t  fi; \\"
      print "\t  sleep 0.5; \\"
      print "\tdone; \\"
      print "\tif [ -z \"$$DISK\" ] || [ ! -b \"$$DISK\" ]; then \\"
      print "\t  if [ -n \"$(DEVICE)\" ] && [ -b \"$(DEVICE)\" ]; then DISK=\"$(DEVICE)\"; fi; \\"
      print "\tfi; \\"
      print "\tif [ -z \"$$DISK\" ] || [ ! -b \"$$DISK\" ]; then \\"
      print "\t  echo \"[host-expand] ERROR: could not resolve SD disk by label or $(DEVICE)\"; exit 1; \\"
      print "\tfi; \\"
      print "\techo \"[make] expanding on $$DISK\"; \\"
      print "\tsfx=\"\"; case \"$$DISK\" in *mmcblk*|*nvme*) sfx=\"p\";; esac; \\"
      print "\tROOT_PART=\"$$DISK$${sfx}2\"; \\"
      print "\tpartprobe \"$$DISK\" || true; sync; \\"
      print "\tparted -s \"$$DISK\" unit % print >/dev/null; \\"
      print "\tparted -s \"$$DISK\" -- resizepart 2 100%; \\"
      print "\tpartprobe \"$$DISK\" || true; sync; \\"
      print "\te2fsck -fp \"$$ROOT_PART\" || true; \\"
      print "\tresize2fs \"$$ROOT_PART\"; \\"
      print "\techo \"[make] expand done\""
      next
    }
    # Skip old recipe lines until next target
    if (in==1) {
      # A new target starts at a non-indented line that looks like a make target (foo:)
      if ($0 ~ /^[^[:space:]][^=]*:[^=]*$/) {
        in=0
        print $0
      }
      next
    }
    print $0
  }
' "$mf" > "$tmp"

mv "$tmp" "$mf"
echo "[patch] updated $mf"
