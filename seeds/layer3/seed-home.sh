#!/usr/bin/env bash
set -Eeuo pipefail
# Seed Layer 3: Nix (multi-user) + Home Manager on Arch target (host-side)
# Adds on the TARGET rootfs:
#   - /usr/local/sbin/sysclone-layer3-home.sh
#   - /etc/systemd/system/sysclone-layer3-home.service (+ enabled via symlink)
#   - /etc/sysclone/home/{flake.nix,home.nix}
# Does NOT chroot.

ROOT_MNT="${ROOT_MNT:?ROOT_MNT is required}"
USERNAME="${USERNAME:-username}"
HM_USER="${HM_USER:-$USERNAME}"

install -d -m 755 \
  "$ROOT_MNT/usr/local/sbin" \
  "$ROOT_MNT/etc/systemd/system" \
  "$ROOT_MNT/etc/sysclone/home" \
  "$ROOT_MNT/var/lib/sysclone" \
  "$ROOT_MNT/etc/nix" \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"

# ----- On-target runner (oneshot) -----
cat > "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh" <<'EOSRUN'
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=/root

STAMP="/var/lib/sysclone/.layer3-home-done"
if [[ -f "$STAMP" ]]; then echo "[layer3] already applied"; exit 0; fi

ENV_FILE="/etc/sysclone/firstboot.env"
if [[ -r "$ENV_FILE" ]]; then . "$ENV_FILE"; fi
: "${USERNAME:=__HM_USER__}"; export USERNAME
log(){ printf '%s %s\n' "[layer3]" "$*"; }

# Ensure curl present (Arch)
if ! command -v curl >/dev/null 2>&1; then
  log "installing curl (pacman)"
  pacman --noconfirm -Sy curl ca-certificates || true
fi

# Install Nix (multi-user), fully non-interactive, official installer
if [[ ! -d /nix ]]; then
  log "installing nix (multi-user, daemon)"
  sh <(curl -fsSL https://nixos.org/nix/install) --daemon --yes
fi

# Make nix CLI available in this shell
if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Basic nix config
install -d -m 755 /etc/nix
cat >/etc/nix/nix.conf <<'EONC'
experimental-features = nix-command flakes
auto-optimise-store = true
max-jobs = auto
EONC

systemctl daemon-reload || true
systemctl enable --now nix-daemon.service || true

HM_DIR="/etc/sysclone/home"
if [[ ! -f "$HM_DIR/flake.nix" ]]; then log "HM flake missing at $HM_DIR; aborting"; exit 1; fi
if ! id -u "$USERNAME" >/dev/null 2>&1; then log "user $USERNAME missing"; exit 1; fi
chown -R "$USERNAME:$USERNAME" "$HM_DIR"

# Ensure user XDG dirs exist (for nix run cache etc.)
install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.cache"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.cache/nix"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.local/state"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.local/share"

# Run Home-Manager via nix run (pinned rev; longer connect timeout)
export NIX_CONFIG="experimental-features = nix-command flakes"
USER_PATH="/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"
HM_SRC="github:nix-community/home-manager?rev=004753ae6b04c4b18aa07192c1106800aaacf6c3"

log "home-manager switch for $USERNAME via nix run (pinned)"
sudo -u "$USERNAME" env -i \
  HOME="/home/$USERNAME" \
  USER="$USERNAME" \
  LOGNAME="$USERNAME" \
  PATH="$USER_PATH" \
  XDG_CACHE_HOME="/home/$USERNAME/.cache" \
  XDG_CONFIG_HOME="/home/$USERNAME/.config" \
  XDG_STATE_HOME="/home/$USERNAME/.local/state" \
  NIX_CONFIG="$NIX_CONFIG" \
  nix --option connect-timeout 60 --option http-connections 1 \
  run "${HM_SRC}#home-manager" -- \
    switch --flake "$HM_DIR#${USERNAME}"

touch "$STAMP"; log "done"
EOSRUN

chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh"

# Bake the HM user into the on-target runner
sed -i "s/__HM_USER__/${HM_USER//\//\/}/" "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh"

# ----- systemd unit on target (enabled by symlink; no chroot) -----
cat > "$ROOT_MNT/etc/systemd/system/sysclone-layer3-home.service" <<'EOUNIT'
[Unit]
Description=SysClone Layer3: Install Nix + Home Manager and apply home config
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-layer3-home.sh
Environment=HOME=/root
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOUNIT

# Enable by creating the wants/ symlink on the target rootfs
ln -sf ../sysclone-layer3-home.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer3-home.service"

# ----- Minimal HM flake (pinned) if missing -----
if [[ ! -f "$ROOT_MNT/etc/sysclone/home/flake.nix" ]]; then
  cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'EOFLAKE'
{
  description = "sysclone HM seed";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
  # Pin HM to avoid GitHub HEAD lookups on first boot
  inputs.home-manager.url = "github:nix-community/home-manager?rev=004753ae6b04c4b18aa07192c1106800aaacf6c3";
  inputs.home-manager.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, home-manager, ... }:
    let mk = user: system:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        modules = [ ./home.nix { home.username = user; home.homeDirectory = "/home/${user}"; } ];
      };
    in {
      homeConfigurations = {
        username-aarch64 = mk "username" "aarch64-linux";
      };
    };
}
EOFLAKE
fi

if [[ ! -f "$ROOT_MNT/etc/sysclone/home/home.nix" ]]; then
  cat > "$ROOT_MNT/etc/sysclone/home/home.nix" <<'EOHOME'
{ config, pkgs, ... }:
{
  programs.home-manager.enable = true;
  home.stateVersion = "24.05";
  home.packages = with pkgs; [ git ripgrep ];
}
EOHOME
fi
