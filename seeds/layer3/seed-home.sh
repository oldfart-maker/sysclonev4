#!/usr/bin/env bash
set -Eeuo pipefail
# Seed Layer 3: Nix (multi-user) + Home Manager on Arch target (host-side)
# Writes to TARGET rootfs:
#   - /usr/local/sbin/sysclone-layer3-home.sh
#   - /etc/systemd/system/sysclone-layer3-home.service (+ enabled)
#   - /etc/sysclone/home/{flake.nix,home.nix} (home.nix if missing)
#   - /etc/sysclone/home/vendor/home-manager (if vendored on host)
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

# Copy vendored dependencies if present on HOST into the CARD
if [[ -d "seeds/layer3/vendor" ]]; then
  mkdir -p "$ROOT_MNT/etc/sysclone/home/vendor"
  cp -a "seeds/layer3/vendor/." "$ROOT_MNT/etc/sysclone/home/vendor/"
fi

# ---------------- On-target runner (oneshot) ----------------
cat > "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh" <<'EOS'
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

# Install Nix (multi-user)
if [[ ! -d /nix ]]; then
  log "installing nix (multi-user, daemon)"
  sh <(curl -fsSL https://nixos.org/nix/install) --daemon --yes
fi

# Make nix CLI available in this shell if profile exists
if [[ -r /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Base nix config (+ trust the HM user to avoid restricted-setting warnings)
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
if [[ ! -f "$HM_DIR/flake.nix" ]]; then log "HM flake missing at $HM_DIR; aborting"; exit 1; fi
if ! id -u "$USERNAME" >/dev/null 2>&1; then log "user $USERNAME missing"; exit 1; fi
chown -R "$USERNAME:$USERNAME" "$HM_DIR"

# Ensure user dirs
install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.cache"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.config"
install -d -m 700 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.local/state"
install -d -m 755 -o "$USERNAME" -g "$USERNAME" "/home/$USERNAME/.local/share"

# Prefer vendored Home Manager if present (avoids GitHub on first boot)
if [[ -d "$HM_DIR/vendor/home-manager" ]]; then
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
  log "home-manager switch (attempt $i/$attempts)"
  if run_hm_switch; then
    touch "$STAMP"; log "done"; exit 0
  fi
  sleep $(( i*i ))
done

log "home-manager failed after $attempts attempts"
exit 1
EOS

chmod 0755 "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh"
sed -i "s/__HM_USER__/${HM_USER//\//\/}/" "$ROOT_MNT/usr/local/sbin/sysclone-layer3-home.sh"

# ---------------- systemd unit on target ----------------
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

# ---------------- Always write vendor-aware flake.nix on CARD ----------------
if [[ -d "$ROOT_MNT/etc/sysclone/home/vendor/nixpkgs" && -d "$ROOT_MNT/etc/sysclone/home/vendor/home-manager" ]]; then
  cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'FLK'
{
  description = "SysClone Layer3 flake (vendored nixpkgs + home-manager)";
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
      inherit pkgs; modules = [ ./home.nix ];
    };
  };
}
FLK
elif [[ -d "$ROOT_MNT/etc/sysclone/home/vendor/home-manager" ]]; then
  cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'FLK'
{
  description = "SysClone Layer3 flake (vendored HM; github nixpkgs)";
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
      inherit pkgs; modules = [ ./home.nix ];
    };
  };
}
FLK
else
  cat > "$ROOT_MNT/etc/sysclone/home/flake.nix" <<'FLK'
{
  description = "SysClone Layer3 flake (github fallback)";
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
      inherit pkgs; modules = [ ./home.nix ];
    };
  };
}
FLK
fi
sed -i "s/USERNAME_PLACEHOLDER/${HM_USER//\//\/}/" "$ROOT_MNT/etc/sysclone/home/flake.nix"
