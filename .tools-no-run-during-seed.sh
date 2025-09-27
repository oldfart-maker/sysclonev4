#!/usr/bin/env bash
set -euo pipefail

changed=0

# 1) Export the guard in the seeder (right after inputs)
if grep -n -q '^USERPASS=' tools/seed-first-boot-service.sh; then
  awk '
    { print }
    $0 ~ /^USERPASS=/ && !done {
      print "export SYSCLONE_SEED_PHASE=1  # prevent accidental execution during seeding"
      print ""
      done=1
    }
  ' tools/seed-first-boot-service.sh > tools/seed-first-boot-service.sh.__new__
  mv tools/seed-first-boot-service.sh.__new__ tools/seed-first-boot-service.sh
  chmod +x tools/seed-first-boot-service.sh
  changed=1
fi

# 2) Add an early-exit guard to the first-boot scripts (whichever exist)
add_guard () {
  local f="$1"
  [ -f "$f" ] || return 0
  # Insert after shebang (or at line 1 if no shebang)
  awk '
    NR==1 {
      print $0
      if ($0 !~ /^#!/) {
        print "#!/usr/bin/env bash"
      }
      print "set -Eeuo pipefail"
      print "# Exit immediately if running during host-side seeding"
      print ' "'"'"'if [[ "${SYSCLONE_SEED_PHASE:-0}" = "1" ]]; then exit 0; fi'"'"'"
      next
    }
    { print }
  ' "$f" > "$f.__new__"
  mv "$f.__new__" "$f"
  chmod +x "$f"
  changed=1
}

add_guard seeds/layer1/first-boot.sh
add_guard seeds/layer1/first-boot-wifi.sh

if [ "$changed" = 1 ]; then
  echo "[patch] Added seed-phase guard and exporter."
else
  echo "[patch] Nothing to change."
fi
