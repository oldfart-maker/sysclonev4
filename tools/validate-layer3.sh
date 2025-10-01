#!/usr/bin/env bash
set -Eeuo pipefail

ok(){   printf '[validate-layer3] OK:   %s\n' "$*"; }
warn(){ printf '[validate-layer3] WARN: %s\n' "$*"; }
fail(){ printf '[validate-layer3] FAIL: %s\n' "$*"; exit 1; }

SEED="seeds/layer3/seed-home.sh"
MK="mk/layer3.mk"

# --- 1) Files exist ---
[[ -f "$SEED" ]] || fail "missing $SEED"
[[ -f "$MK"   ]] || fail "missing $MK"
ok "seed + mk present"

# --- 2) Runner target path present ---
TARGET_PATH_REGEX='/usr/local/sbin/sysclone-layer3-home\.sh'
if ! grep -Fq '/usr/local/sbin/sysclone-layer3-home.sh' "$SEED"; then
  fail "seed-home.sh does not reference /usr/local/sbin/sysclone-layer3-home.sh"
fi

# --- 3) Writer style (accept any of: cat+heredoc, tee+heredoc, install -D /dev/stdin) ---
has_cat_heredoc=false
has_tee_heredoc=false
has_install_stdin=false

grep -Eq "cat[[:space:]]*>[[:space:]]*\"?\$ROOT_MNT$TARGET_PATH_REGEX\"?[[:space:]]*<<'?[[:alnum:]_]+'?" "$SEED" && has_cat_heredoc=true
grep -Eq "sudo[[:space:]]+tee[[:space:]]+\"?\$ROOT_MNT$TARGET_PATH_REGEX\"?[[:space:]]*>/dev/null[[:space:]]*<<'?[[:alnum:]_]+'?" "$SEED" && has_tee_heredoc=true
grep -Eq "sudo[[:space:]]+install[[:space:]]+-D[[:space:]]+-m[[:space:]]+0755[[:space:]]+/dev/stdin[[:space:]]+\"?\$ROOT_MNT$TARGET_PATH_REGEX\"?" "$SEED" && has_install_stdin=true

if $has_cat_heredoc || $has_tee_heredoc || $has_install_stdin; then
  ok "on-target runner installation present (cat/tee heredoc or install -D /dev/stdin)"
else
  fail "seed-home.sh does not install the on-target runner (expected cat <<EOF, tee <<EOF, or install -D /dev/stdin)"
fi

# --- 4) Optional: warn if HOME not exported in runner body ---
if grep -Eq "^export[[:space:]]+HOME=/?root|^export[[:space:]]+HOME=\"?\$HOME:?/?root" "$SEED"; then
  ok "runner exports HOME (non-interactive installers safe)"
else
  warn "runner body does not show 'export HOME=/root' — may be fine if you set it via the unit"
fi
