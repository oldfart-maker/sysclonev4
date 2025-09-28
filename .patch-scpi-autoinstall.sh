#!/usr/bin/env bash
set -euo pipefail
f=tools/payloads/usr-local-bin/scpi
mkdir -p "$(dirname "$f")"
cat > "$f" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if ! command -v make >/dev/null 2>&1; then
  echo "[scpi] 'make' not found."
  if command -v pacman >/dev/null 2>&1; then
    echo "[scpi] installing 'make' with pacman…"
    sudo pacman -Sy --needed --noconfirm make || {
      echo "[scpi] failed to install 'make'"; exit 1; }
  else
    echo "[scpi] please install 'make' with your package manager."; exit 1
  fi
fi
exec make -f /usr/local/share/sysclone/pi.mk "$@"
EOF
chmod +x "$f"
echo "[ok] updated payload: $f"
