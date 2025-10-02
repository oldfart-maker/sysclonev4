#!/usr/bin/env bash
set -Eeuo pipefail
# Seed Layer 3: Nix (multi-user) + Home Manager on Arch target (host-side)
# Writes onto TARGET rootfs:
#   - /usr/local/sbin/sysclone-layer3-home.sh  (runtime-smart, auto-username)
#   - /etc/systemd/system/sysclone-layer3-home.service
#   - /etc/sysclone/home/{flake.nix,home.nix,modules/00-user.nix}
#   - /etc/sysclone/home/vendor/{home-manager,nixpkgs} (copied from repo if present)
# Does NOT chroot.

ROOT_MNT="${ROOT_MNT:?ROOT_MNT is required}"
USERNAME="${USERNAME:-username}"
HM_USER="${HM_USER:-$USERNAME}"

install -d -m 755 \
  "$ROOT_MNT/usr/local/sbin" \
  "$ROOT_MNT/etc/systemd/system" \
  "$ROOT_MNT/etc/sysclone/home" \
  "$ROOT_MNT/etc/sysclone/home/vendor" \
  "$ROOT_MNT/etc/sysclone/home/modules" \
  "$ROOT_MNT/var/lib/sysclone" \
  "$ROOT_MNT/etc/nix" \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants"

# ---------- copy vendored submodules from HOST to CARD (if present) ----------
if [[ -d "seeds/layer3/vendor/home-manager" ]]; then
  rsync -a --delete "seeds/layer3/vendor/home-manager/" "$ROOT_MNT/etc/sysclone/home/vendor/home-manager/"
fi
if [[ -d "seeds/layer3/vendor/nixpkgs" ]]; then
  rsync -a --delete "seeds/layer3/vendor/nixpkgs/" "$ROOT_MNT/etc/sysclone/home/vendor/nixpkgs/"
fi

# ---------- write vendor-aware flake.nix on the CARD (leave USERNAME_PLACEHOLDER) ----------
if [[ -d "$ROOT_MNT/etc/sysclone/home/vendor/nixpkgs/.git" && -d "$ROOT_MNT/etc/sysclone/home/vendor/home-manager/.git" ]]; then
  cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'FLK'
{
  description = "SysClone L3 flake (vendored nixpkgs + home-manager)";
  inputs = {
    nixpkgs.url = "path:./vendor/nixpkgs";
    home-manager.url = "path:./vendor/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, home-manager, ... }:
  let
    system = "aarch64-linux";
    username = "USERNAME_PLACEHOLDER";
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
  in {
    homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
      inherit pkgs; modules = [ ./modules/00-user.nix ./home.nix ];
    };
  };
}
FLK
elif [[ -d "$ROOT_MNT/etc/sysclone/home/vendor/home-manager/.git" ]]; then
  cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'FLK'
{
  description = "SysClone L3 flake (vendored HM; github nixpkgs)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager.url = "path:./vendor/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, home-manager, ... }:
  let
    system = "aarch64-linux";
    username = "USERNAME_PLACEHOLDER";
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
  in {
    homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
      inherit pkgs; modules = [ ./modules/00-user.nix ./home.nix ];
    };
  };
}
FLK
else
  cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'FLK'
{
  description = "SysClone L3 flake (github fallback)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, home-manager, ... }:
  let
    system = "aarch64-linux";
    username = "USERNAME_PLACEHOLDER";
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
  in {
    homeConfigurations.${username} = home-manager.lib.homeManagerConfiguration {
      inherit pkgs; modules = [ ./modules/00-user.nix ./home.nix ];
    };
  };
}
FLK
fi

# minimal home.nix (only if absent); leave USERNAME_PLACEHOLDER
if [[ ! -f "$ROOT_MNT/etc/sysclone/home/home.nix" ]]; then
  cat > "$ROOT_MNT/etc/sysclone/home/home.nix" <<'HOME'
{ config, pkgs, ... }:
{
  programs.home-manager.enable = true;
  home.username = "USERNAME_PLACEHOLDER";
  home.homeDirectory = "/home/USERNAME_PLACEHOLDER";
  home.stateVersion = "24.05";
  home.packages = with pkgs; [ git ripgrep ];
}
HOME
fi

# guard module: ALWAYS write, idempotent overwrite
cat > "$ROOT_MNT/etc/sysclone/home/modules/00-user.nix" <<'USR'
{ config, pkgs, ... }: {
  home.username = "USERNAME_PLACEHOLDER";
  home.homeDirectory = "/home/USERNAME_PLACEHOLDER";
}
USR

# ---------- on-target runner (auto-username; 3 sed substitutions; retries) ----------
cat > "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
export HOME=/root

STAMP="/var/lib/sysclone/.layer3-home-done"
[[ -f "$STAMP" ]] && { echo "[layer3] already applied"; exit 0; }

# Optional env from firstboot
ENV_FILE="/etc/sysclone/firstboot.env"
[[ -r "$ENV_FILE" ]] && . "$ENV_FILE"

# Resolve USERNAME:
# 1) env; 2) first uid>=1000; 3) "username"
if [[ -z "${USERNAME:-}" ]]; then
  USERNAME="$(awk -F: '$3>=1000 && $1!="nobody"{print $1; exit}' /etc/passwd || true)"
  USERNAME="${USERNAME:-username}"
fi
export USERNAME
log(){ printf '%s %s\n' "[layer3]" "$*"; }

# Ensure curl present (Arch)
if ! command -v curl >/dev/null 2>&1; then
  log "installing curl (pacman)"
  pacman --noconfirm -Sy curl ca-certificates || true
fi

# Install Nix (multi-user)
if [[ ! -d /nix ]]; then
  log "installing nix (multi-user, daemon)"
  sh <(curl -fsSL https://nixos.org/nix/install) --daemon --yes
fi

# Make nix CLI available
if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Nix config (trust USERNAME to avoid restricted-setting warnings)
install -d -m 755 /etc/nix
cat >/etc/nix/nix.conf <<EONC
experimental-features = nix-command flakes
auto-optimise-store = true
max-jobs = auto
trusted-users = root ${USERNAME}
EONC

systemctl daemon-reload || true
systemctl enable --now nix-daemon.service || true

HM_DIR="/etc/sysclone/home"
if [[ ! -f "$HM_DIR/flake.nix" ]]; then log "HM flake missing at $HM_DIR"; exit 1; fi
if ! id -u "$USERNAME" >/dev/null 2>&1; then log "user $USERNAME missing"; exit 1; fi

# Substitute USERNAME_PLACEHOLDER in all seeded files (idempotent)
sed -i "s/USERNAME_PLACEHOLDER/${USERNAME//\//\\/}/" "$HM_DIR/flake.nix" || true
sed -i "s/USERNAME_PLACEHOLDER/${USERNAME//\//\\/}/" "$HM_DIR/home.nix" || true
sed -i "s/USERNAME_PLACEHOLDER/${USERNAME//\//\\/}/" "$HM_DIR/modules/00-user.nix" || true

chown -R "$USERNAME:$USERNAME" "$HM_DIR"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.cache" "/home/$USERNAME/.config" "/home/$USERNAME/.local/state"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.local/share"

# Prefer vendored Home Manager if present
if [[ -d "$HM_DIR/vendor/home-manager/.git" ]]; then
  HM_SRC="$HM_DIR/vendor/home-manager"
else
  HM_SRC="github:nix-community/home-manager?rev=004753ae6b04c4b18aa07192c1106800aaacf6c3"
fi

export NIX_CONFIG="experimental-features = nix-command flakes"
USER_PATH="/nix/var/nix/profiles/default/bin:/usr/local/bin:/usr/bin:/bin"

run_hm_switch() {
  sudo -u "$USERNAME" \
    env -i HOME="/home/$USERNAME" USER="$USERNAME" LOGNAME="$USERNAME" PATH="$USER_PATH" \
    XDG_CACHE_HOME="/home/$USERNAME/.cache" \
    XDG_CONFIG_HOME="/home/$USERNAME/.config" \
    XDG_STATE_HOME="/home/$USERNAME/.local/state" \
    nix --option connect-timeout 120 --option http-connections 1 \
        run "$HM_SRC"#home-manager -- switch --flake "$HM_DIR#$USERNAME"
}

attempts=5
for i in $(seq 1 "$attempts"); do
  log "home-manager switch (attempt $i/$attempts) for $USERNAME"
  if run_hm_switch; then
    touch "$STAMP"; log "done"; exit 0
  fi
  sleep $(( i*i ))
done

log "home-manager failed after $attempts attempts"
exit 1
EOS
chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh"

# ---------- systemd unit ----------
cat > "$ROOT_MNT/etc/systemd/system/sysclone-layer3-home.service" <<'UNIT'
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
UNIT

ln -sf ../sysclone-layer3-home.service \
  "$ROOT_MNT/etc/systemd/system/multi-user.target.wants/sysclone-layer3-home.service"
