#!/usr/bin/env bash
set -Eeuo pipefail

fail() { echo "[validate-layer3] FAIL: $*" >&2; exit 1; }
ok()   { echo "[validate-layer3] OK:   $*"; }

# 1) Files exist
[[ -f seeds/layer3/seed-home.sh ]] || fail "missing seeds/layer3/seed-home.sh"
[[ -f mk/layer3.mk ]] || fail "missing mk/layer3.mk"
ok "seed + mk present"

# 2) seed-home.sh critical patterns
grep -qE '^sudo install -D -m 0755 /dev/stdin "\$ROOT_MNT/usr/local/sbin/sysclone-layer3-home\.sh"' seeds/layer3/seed-home.sh \
  || fail "seed-home.sh does not install the on-target runner via heredoc"

grep -q 'export HOME=/root' seeds/layer3/seed-home.sh \
  || fail "on-target runner is not exporting HOME=/root (in heredoc)"

grep -q -- '--no-confirm --daemon' seeds/layer3/seed-home.sh \
  || fail "determinate installer not forced non-interactive"

grep -q -- '--daemon --yes' seeds/layer3/seed-home.sh \
  || fail "official installer not forced non-interactive"

grep -q 'Environment=HOME=/root' seeds/layer3/seed-home.sh \
  || fail "systemd unit does not set Environment=HOME=/root"

grep -q 'sysclone-layer3-home.service.d/env.conf' seeds/layer3/seed-home.sh \
  || fail "drop-in env.conf not created"

grep -q "nix run 'github:nix-community/home-manager#home-manager' --" seeds/layer3/seed-home.sh \
  || fail "HM switch via nix run not found"

ok "patterns present in seed-home.sh"

# 3) Top-level Makefile includes our layer3.mk
grep -q -- '-include mk/layer3.mk' Makefile \
  || fail "top-level Makefile does not include mk/layer3.mk"

ok "Makefile includes mk/layer3.mk"

echo "[validate-layer3] All checks passed."
