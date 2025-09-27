#!/usr/bin/env bash
set -euo pipefail

SEED=seeds/layer2.5/seed-greetd.sh
[[ -f "$SEED" ]] || { echo "missing $SEED"; exit 2; }

# verify source files exist
[[ -f seeds/layer2.5/sysclone-layer2.5-greetd.service ]] || { echo "missing seeds/layer2.5/sysclone-layer2.5-greetd.service"; exit 2; }
[[ -f seeds/layer2.5/l25-greetd-install.sh ]]           || { echo "missing seeds/layer2.5/l25-greetd-install.sh"; exit 2; }

# append once (search for the unit filename; if absent, append at end)
if ! grep -q 'sysclone-layer2.5-greetd.service' "$SEED"; then
  cat >> "$SEED" <<'EOF'

# ---- L2.5 oneshot (install + enable) -----------------------------------------
echo "[l2.5] install oneshot: sysclone-layer2.5-greetd.service + l25-greetd-install.sh"
install -D -m 0644 "seeds/layer2.5/sysclone-layer2.5-greetd.service" \
  "$ROOT_MNT/etc/systemd/system/sysclone-layer2.5-greetd.service"

install -D -m 0755 "seeds/layer2.5/l25-greetd-install.sh" \
  "$ROOT_MNT/usr/local/lib/sysclone/l25-greetd-install.sh"

install -d -m 0755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
ln -sf ../sysclone-layer2.5-greetd.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer2.5-greetd.service"
# ------------------------------------------------------------------------------
EOF
  chmod +x "$SEED"
  echo "[l2.5] appended oneshot install+enable to $SEED"
else
  echo "[l2.5] $SEED already contains oneshot lines; no change."
fi
