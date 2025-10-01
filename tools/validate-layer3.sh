#!/usr/bin/env bash
set -Eeuo pipefail

fail() { echo "[validate-layer3] FAIL: $*" >&2; exit 1; }
ok()   { echo "[validate-layer3] OK:   $*"; }

# 1) Files exist
[[ -f seeds/layer3/seed-home.sh ]] || fail "missing seeds/layer3/seed-home.sh"
[[ -f mk/layer3.mk ]] || fail "missing mk/layer3.mk"
ok "seed + mk present"

SEED="seeds/layer3/seed-home.sh"

# 2) On-target runner is installed (accept tee OR install -D heredoc)
if grep -qE '^sudo install -D -m 0755 /dev/stdin "\$ROOT_MNT/usr/local/sbin/sysclone-layer3-home\.sh"' "$SEED" \
   || grep -qE '^sudo tee "\$ROOT_MNT/usr/local/sbin/sysclone-layer3-home\.sh"' "$SEED"; then
  ok "on-target runner install command found (tee/install -D)"
else
  fail "seed-home.sh does not install the on-target runner (tee or install -D heredoc)"
fi

# 3) HOME is set to /root in runner content
grep -q 'export HOME=/root' "$SEED" \
  && ok "runner exports HOME=/root" \
  || fail "runner does not export HOME=/root"

# 4) Non-interactive installers: at least one path must be present
if grep -q -- '--no-confirm --daemon' "$SEED" || grep -q -- '--daemon --yes' "$SEED"; then
  ok "non-interactive nix installer flags present"
else
  fail "non-interactive nix installer flags not detected"
fi

# 5) systemd drop-in that sets HOME=/root
grep -q 'sysclone-layer3-home.service.d/env.conf' "$SEED" \
  && grep -q 'Environment=HOME=/root' "$SEED" \
  && ok "systemd drop-in sets HOME=/root" \
  || fail "systemd drop-in for HOME=/root missing"

# 6) HM switch via nix run (works even if home-manager binary not in PATH)
grep -q "nix run 'github:nix-community/home-manager#home-manager' --" "$SEED" \
  && ok "HM switch via nix run present" \
  || fail "HM switch via nix run not found"

# 7) Top-level Makefile includes layer3.mk
grep -q -- '-include mk/layer3.mk' Makefile \
  && ok "Makefile includes mk/layer3.mk" \
  || fail "top-level Makefile does not include mk/layer3.mk"

echo "[validate-layer3] All checks passed."
