#!/usr/bin/env bash
set -Eeuo pipefail
BOOT_MNT="${BOOT_MNT:-/mnt/sysclone-boot}"
ROOT_MNT="${ROOT_MNT:-/mnt/sysclone-root}"

log(){ echo "[boot-visibility] $*"; }

# --- A) Kernel cmdline: turn ON status, turn OFF quiet/splash ---
if [[ -f "$BOOT_MNT/cmdline.txt" ]]; then
  log "patching $BOOT_MNT/cmdline.txt"
  sudo sed -i \
    -e 's/[[:space:]]\+quiet\>//g' \
    -e 's/[[:space:]]\+splash\>//g' \
    -e 's/$/ systemd.show_status=1/' \
    "$BOOT_MNT/cmdline.txt"
else
  log "WARN: $BOOT_MNT/cmdline.txt not found (skipping)"
fi

# --- B) Ensure status dir on BOOT ---
sudo mkdir -p "$BOOT_MNT/sysclone-status"
sudo chmod 0777 "$BOOT_MNT/sysclone-status" || true

# --- Helpers ---
add_service_console() {
  local svc="$1"
  if [[ -f "$svc" ]]; then
    if ! grep -q '^StandardOutput=.*console' "$svc"; then
      log "add console output to $(basename "$svc")"
      sudo awk '
        BEGIN{added=0}
        /^\[Service\]$/ { print; print "StandardOutput=journal+console"; print "StandardError=journal+console"; added=1; next }
        { print }
        END{ if(!added) print "[Service]\nStandardOutput=journal+console\nStandardError=journal+console" }
      ' "$svc" | sudo tee "$svc.__new__" >/dev/null
      sudo mv "$svc.__new__" "$svc"
    else
      log "console already enabled for $(basename "$svc")"
    fi
  fi
}

add_script_tee() {
  local script="$1" logname="$2"
  if [[ -f "$script" ]]; then
    # If it already tees to sysclone-status or tty, skip
    if ! grep -q 'sysclone-status' "$script" && ! grep -q '/dev/tty1' "$script"; then
      log "adding tee -> /boot/sysclone-status/$logname and /dev/tty1 to $(basename "$script")"
      sudo awk -v LOG="$logname" -v BOOT="$BOOT_MNT" '
        NR==1 {
          print "# sysclone visibility: mirror output to BOOT and tty1"
          print "mkdir -p " BOOT "/sysclone-status || true"
          print "exec > >(tee -a " BOOT "/sysclone-status/" LOG " /dev/tty1) 2>&1"
        }
        { print }
      ' "$script" | sudo tee "$script.__new__" >/dev/null
      sudo mv "$script.__new__" "$script"
      sudo chmod +x "$script" || true
    else
      log "tee already present in $(basename "$script")"
    fi
  fi
}

# --- C) Services: print to console ---
add_service_console "$ROOT_MNT/etc/systemd/system/sysclone-first-boot.service"
add_service_console "$ROOT_MNT/etc/systemd/system/sysclone-layer2-install.service"
add_service_console "$ROOT_MNT/etc/systemd/system/sysclone-layer2.5-greetd-install.service"

# --- D) Scripts: tee to /boot and /dev/tty1 ---
add_script_tee "$ROOT_MNT/usr/local/lib/sysclone/first-boot-provision.sh"      "firstboot.log"
add_script_tee "$ROOT_MNT/usr/local/sbin/sysclone-first-boot.sh"               "firstboot-script.log"
add_script_tee "$ROOT_MNT/usr/local/sbin/sysclone-layer2-install.sh"           "layer2-install.log"
add_script_tee "$ROOT_MNT/usr/local/sbin/sysclone-layer2.5-greetd-install.sh"  "layer2.5-install.log"

log "done (visibility enabled)."
