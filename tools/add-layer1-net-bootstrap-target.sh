#!/usr/bin/env bash
set -euo pipefail

mf="Makefile"
bak="Makefile.bak.$(date +%Y%m%d%H%M%S)"
cp -f "$mf" "$bak"

# ---- A) Add the standalone target if missing ----
if ! grep -q '^seed-layer1-net-bootstrap:' "$mf"; then
  cat >> "$mf" <<'EOF'

# Layer1: stage network/clock/mirrors bootstrap (runs once on target)
seed-layer1-net-bootstrap: ensure-mounted  ## Layer1: seed net/clock/certs bootstrap (on-target)
	@echo "[layer1] net-bootstrap via tools/seed-net-bootstrap.sh"
	sudo env ROOT_MNT="$(ROOT_MNT)" bash tools/seed-net-bootstrap.sh

EOF
  echo "[patch] appended target seed-layer1-net-bootstrap"
else
  echo "[patch] target seed-layer1-net-bootstrap already present (skipping append)"
fi

# ---- B) Ensure the aggregate calls it after expand-rootfs and before first-boot-service ----
# We rewrite only the recipe block of seed-layer1-all, inserting our call if absent.
perl -0777 -pe '
  # find the seed-layer1-all recipe block
  if (m/^seed-layer1-all:[^\n]*\n(\t[^\n]*\n)+/m) {
    my $block = $&;

    # if the call is absent, insert it after the expand-rootfs line
    if ($block !~ /^\t\$\([Mm][Aa][Kk][Ee]\) seed-layer1-net-bootstrap/m) {
      $block =~ s/^\t\$\([Mm][Aa][Kk][Ee]\) seed-layer1-expand-rootfs; \\\n/\t$(MAKE) seed-layer1-expand-rootfs; \\\n\t$(MAKE) seed-layer1-net-bootstrap; \\\n/m
        or $block =~ s/^\t\$\([Mm][Aa][Kk][Ee]\) seed-layer1-expand-rootfs\n/\t$(MAKE) seed-layer1-expand-rootfs\n\t$(MAKE) seed-layer1-net-bootstrap\n/m;

      # splice modified block back
      s/^seed-layer1-all:[^\n]*\n(\t[^\n]*\n)+/$block/m;
    }
  }
' -i "$mf"

echo "[patch] updated $mf (backup at $bak)"
