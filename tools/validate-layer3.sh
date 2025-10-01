#!/usr/bin/env bash
set -Eeuo pipefail

ok(){   printf '[validate-layer3] OK:   %s\n' "$*"; }
warn(){ printf '[validate-layer3] WARN: %s\n' "$*"; }
fail(){ printf '[validate-layer3] FAIL: %s\n' "$*"; exit 1; }

SEED="seeds/layer3/seed-home.sh"
MK="mk/layer3.mk"

# 1) Files exist
[[ -f "$SEED" ]] || fail "missing $SEED"
[[ -f "$MK"   ]] || fail "missing $MK"
ok "seed + mk present"

# 2) On-target runner install method (accept cat<<, sudo tee<<, or install -D /dev/stdin)
target_rx='/usr/local/sbin/sysclone-layer3-home\.sh'
has_cat=false
has_tee=false
has_inst=false

grep -Eq "cat[[:space:]]*>[[:space:]]*\"?\$ROOT_MNT${target_rx}\"?[[:space:]]*<<'?[[:alnum:]_]+'?" "$SEED" && has_cat=true
grep -Eq "sudo[[:space:]]+tee[[:space:]]+\"?\$ROOT_MNT${target_rx}\"?[[:space:]]*>/dev/null[[:space:]]*<<'?[[:alnum:]_]+'?" "$SEED" && has_tee=true
grep -Eq "sudo[[:space:]]+install[[:space:]]+-D[[:space:]]+-m[[:space:]]+0755[[:space:]]+/dev/stdin[[:space:]]+\"?\$ROOT_MNT${target_rx}\"?" "$SEED" && has_inst=true

if $has_cat || $has_tee || $has_inst; then
  ok "on-target runner installation present (cat/tee heredoc or install -D /dev/stdin)"
else
  fail "seed-home.sh does not install the on-target runner (expected cat <<EOF, tee <<EOF, or install -D /dev/stdin)"
fi

# 3) Ensure the heredoc body exports HOME=/root (prevents $HOME-not-set during reclone)
#    We look inside the heredoc body by a cheap check against the seed file text.
if grep -Eq '^cat[[:space:]]*>[[:space:]]*"?\$ROOT_MNT'"$target_rx"'"?[[:space:]]*<<' "$SEED"; then
  if grep -Eq '^export[[:space:]]+HOME=/root' "$SEED"; then
    ok "runner sets HOME=/root inside heredoc"
  else
    fail "runner does not set HOME=/root inside heredoc"
  fi
else
  warn "could not statically verify HOME export (non-cat writer); ensure runner exports HOME=/root"
fi

# 4) Make installers non-interactive
# determinate installer should carry --no-confirm
if grep -Eq 'install\.determinate\.systems/nix' "$SEED"; then
  if grep -Eq 'install[[:space:]]+--no-confirm[[:space:]]+--daemon' "$SEED"; then
    ok "determinate installer is non-interactive (--no-confirm)"
  else
    fail "determinate installer missing --no-confirm"
  fi
else
  warn "determinate installer not detected (ok if using official installer fallback)"
fi

# official nix installer should carry --yes
if grep -Eq 'nixos\.org/nix/install' "$SEED"; then
  if grep -Eq '--daemon[[:space:]]+--yes' "$SEED"; then
    ok "official nix installer is non-interactive (--yes)"
  else
    fail "official nix installer missing --yes"
  fi
else
  warn "official installer not detected (ok if determinate path always used)"
fi
