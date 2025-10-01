#!/usr/bin/env bash
set -Eeuo pipefail

ok(){   printf '[validate-layer3] OK:   %s\n' "$*"; }
warn(){ printf '[validate-layer3] WARN: %s\n' "$*"; }
fail(){ printf '[validate-layer3] FAIL: %s\n' "$*"; exit 1; }

SEED="seeds/layer3/seed-home.sh"
MK="mk/layer3.mk"
TARGET_RX='/usr/local/sbin/sysclone-layer3-home\.sh'

[[ -f "$SEED" ]] || fail "missing $SEED"
[[ -f "$MK"   ]] || fail "missing $MK"
ok "seed + mk present"

# Accept any of: cat+heredoc, tee+heredoc, install -D /dev/stdin
runner_line_rx='(^|[[:space:]])(cat|sudo[[:space:]]+cat|tee|sudo[[:space:]]+tee|install|sudo[[:space:]]+install)\b.*sysclone-layer3-home\.sh'
if grep -Eq "$runner_line_rx" "$SEED"; then
  # Further require either a heredoc '<<' on the same/nearby lines OR /dev/stdin usage
  if grep -Eq "$runner_line_rx.*<<|/dev/stdin[[:space:]]+\"?\$ROOT_MNT$TARGET_RX\"?" "$SEED"; then
    ok "runner install found (cat/tee heredoc or install -D /dev/stdin)"
  else
    fail "runner install line present but neither heredoc nor /dev/stdin detected"
  fi
else
  fail "seed-home.sh does not appear to install the on-target runner"
fi

# Try to verify HOME=/root only if we can see the heredoc content in SEED itself
if grep -Eq "cat[[:space:]]*>[[:space:]]*\"?\$ROOT_MNT$TARGET_RX\"?[[:space:]]*<<'?[[:alnum:]_]+'?" "$SEED"; then
  if grep -Eq '^export[[:space:]]+HOME=/root' "$SEED"; then
    ok "runner sets HOME=/root in heredoc body"
  else
    fail "runner heredoc body is missing 'export HOME=/root'"
  fi
else
  warn "runner body not statically visible (tee/install path) — ensure the actual runner exports HOME=/root"
fi

# Non-interactive flags on installers (best-effort)
if grep -Eq 'install\.determinate\.systems/nix' "$SEED"; then
  grep -Eq 'install[[:space:]]+--no-confirm([[:space:]]|$)' "$SEED" \
    && ok "determinate installer: --no-confirm present" \
    || fail "determinate installer missing --no-confirm"
fi

if grep -Eq 'nixos\.org/nix/install' "$SEED"; then
  grep -Eq '--daemon([[:space:]]|$).*--yes|--yes([[:space:]]|$).*--daemon' "$SEED" \
    && ok "official installer: --yes present (non-interactive)" \
    || fail "official installer missing --yes"
fi

# Non-interactive flags on installers (best-effort)

if grep -Eq -- 'install.determinate.systems/nix' ""; then

  grep -Eq -- 'install[[:space:]]+--no-confirm([[:space:]]|1000 3 90 98 108 983 985 986 988 990 991 992 995 998 1000' "" \

    && ok "determinate installer: --no-confirm present" \

    || fail "determinate installer missing --no-confirm"

fi



if grep -Eq -- 'nixos.org/nix/install' ""; then

  # Accept either on the same line (most common) or anywhere in file, but require it if the installer is used

  if grep -Eq -- 'nixos.org/nix/install.*--yes' "" || \

     grep -Eq -- '--yes' ""; then

    ok "official installer: --yes present (non-interactive)"

  else

    fail "official installer missing --yes"

  fi

fi

  