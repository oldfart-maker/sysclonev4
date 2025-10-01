#!/usr/bin/env bash
set -Eeuo pipefail
# Seed Layer 3: Nix (multi-user) + Home Manager on Arch target
# Adds:
#   - /usr/local/sbin/sysclone-layer3-home.sh
#   - /etc/systemd/system/sysclone-layer3-home.service (enabled)
#   - /etc/sysclone/home/{flake.nix,home.nix}
ROOT_MNT="${ROOT_MNT:?ROOT_MNT is required}"
USERNAME="${USERNAME:-username}"

install -d -m 755 \
  "$ROOT_MNT/usr/local/sbin" \
  "$ROOT_MNT/etc/systemd/system" \
  "$ROOT_MNT/etc/sysclone/home" \
  "$ROOT_MNT/var/lib/sysclone" \
  "$ROOT_MNT/etc/nix"

# On-target runner (uses baked __HM_USER__ fallback)
cat > "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh" <<'EOSH'
#!/usr/bin/env bash
set -Eeuo pipefail
STAMP="/var/lib/sysclone/.layer3-home-done"
if [[ -f "$STAMP" ]]; then echo "[layer3] already applied"; exit 0; fi
ENV_FILE="/etc/sysclone/firstboot.env"
if [[ -r "$ENV_FILE" ]]; then . "$ENV_FILE"; fi
: "${USERNAME:=__HM_USER__}"; export USERNAME
log(){ printf '%s %s\n' "[layer3]" "$*"; }

if ! command -v curl >/dev/null 2>&1; then
  log "installing curl (pacman)"; pacman --noconfirm -Sy curl ca-certificates || true
fi

if [[ ! -d /nix ]]; then
  log "installing nix (multi-user, daemon)"
  if ! (curl -fsSL https://install.determinate.systems/nix | sh -s -- install --daemon); then
    sh <(curl -fsSL https://nixos.org/nix/install) --daemon
  fi
fi

if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

install -d -m 755 /etc/nix
cat >/etc/nix/nix.conf <<'EONC'
experimental-features = nix-command flakes
auto-optimise-store = true
max-jobs = auto
EONC

systemctl daemon-reload || true
systemctl enable --now nix-daemon.service || true

if ! command -v home-manager >/dev/null 2>&1; then
  log "installing home-manager"
  nix --extra-experimental-features "nix-command flakes" \
    profile install 'github:nix-community/home-manager#home-manager' || \
  nix --extra-experimental-features "nix-command flakes" \
    profile install nixpkgs#home-manager
fi

HM_DIR="/etc/sysclone/home"
if [[ ! -f "$HM_DIR/flake.nix" ]]; then log "HM flake missing at $HM_DIR; aborting"; exit 1; fi
if ! id -u "$USERNAME" >/dev/null 2>&1; then log "user $USERNAME missing"; exit 1; fi
chown -R "$USERNAME:$USERNAME" "$HM_DIR"

export NIX_CONFIG="experimental-features = nix-command flakes"
log "home-manager switch for $USERNAME"
sudo -u "$USERNAME" --preserve-env=HOME,NIX_CONFIG HOME="/home/$USERNAME" \
  home-manager switch --flake "$HM_DIR#${USERNAME}"

touch "$STAMP"; log "done"
EOSH
chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh"

cat > "$ROOT_MNT/etc/systemd/system/sysclone-layer3-home.service" <<'EOUNIT'
[Unit]
Description=SysClone Layer3: Install Nix + Home Manager and apply home config
Wants=network-online.target
After=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/sysclone-layer3-home.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOUNIT

install -d -m 755 "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
ln -sf ../sysclone-layer3-home.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer3-home.service"

cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'EOFLAKE'
{
  description = "SysClone L3 minimal Home Manager flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, home-manager, ... }:
  let
    system = builtins.currentSystem or "aarch64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    homeConfigurations = {
      __HM_USER__ = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ ./home.nix ];
      };
    };
  };
}
EOFLAKE

cat > "$ROOT_MNT/etc/sysclone/home/home.nix" <<'EOHOME'
{ pkgs, ... }:
{
  home.username = "__HM_USER__";
  home.homeDirectory = "/home/__HM_USER__";
  home.stateVersion = "24.05";

  programs.home-manager.enable = true;
  programs.git.enable = true;

  home.packages = with pkgs; [
    emacs
    ripgrep
    fd
    rofi-wayland
    pywal
  ];

  xdg.configFile."niri/config.kdl".text = ''
    // Managed by Home Manager (SysClone L3)
    output * { mode auto }
  '';
}
EOHOME

sed -i "s/__HM_USER__/${USERNAME}/g" \
  "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh" \
  "$ROOT_MNT/etc/sysclone/home/flake.nix" \
  "$ROOT_MNT/etc/sysclone/home/home.nix"

echo "[layer3] staged nix/home-manager service + minimal flake (user=${USERNAME})"
