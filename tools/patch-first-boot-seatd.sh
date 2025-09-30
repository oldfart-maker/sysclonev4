#!/usr/bin/env bash
set -Eeuo pipefail

# Pick whichever of these exists in your repo
CANDIDATES=(
  "seeds/layer1/first-boot.sh"
  "seeds/layer1/first-boot-provision.sh"
)

TARGET=""
for f in "${CANDIDATES[@]}"; do
  [[ -f "$f" ]] && TARGET="$f" && break
done

[[ -n "$TARGET" ]] || { echo "[patch] ERROR: no first-boot script found under seeds/layer1/"; exit 1; }

# Already patched?
grep -q 'seatd-ensure-start' "$TARGET" && { echo "[patch] already present in $TARGET"; exit 0; }

tmp="$TARGET.__new__"
cp -a "$TARGET" "$tmp"

cat >>"$tmp" <<'PATCH'

# --- seatd-ensure-start (idempotent) -----------------------------------------
# Ensure first user is in required groups and seatd is running (if installed)
{
  USER_NAME="${USERNAME:-username}"
  for g in seat input video render; do
    getent group "$g" >/dev/null 2>&1 || groupadd -r "$g" || true
  done
  usermod -aG seat,input,video,render "$USER_NAME" || true
  if systemctl list-unit-files --no-legend | grep -q '^seatd\.service'; then
    systemctl enable --now seatd.service || true
  fi
  log "seatd/groups ensured for $USER_NAME"
}
# --- seatd-ensure-end ---------------------------------------------------------
PATCH

mv "$tmp" "$TARGET"
chmod +x "$TARGET"
echo "[patch] updated $TARGET"
