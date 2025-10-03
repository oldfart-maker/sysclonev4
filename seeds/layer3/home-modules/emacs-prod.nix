{ config, pkgs, lib, ... }:
let
  emacsPkg = pkgs.emacs29-pgtk or pkgs.emacs29;
  emacsBatch = (pkgs.emacs29-nox or pkgs.emacs29);
in {
  # tools your script expects
  home.packages = with pkgs; [ emacsPkg ripgrep fd mu isync msmtp feh ];

  # ship your snapshot; HM will own it going forward
  home.file.".config/emacs-prod".source = ./../dotfiles/emacs-prod;

  # install helper scripts as executable
  home.file.".local/bin/emacs-profile" = {
    source = ./. + "/../dotfiles/emacs-prod/emacs-common/emacs-profile";
    executable = true;
  };
  home.file.".local/bin/emacsr" = {
    source = ./. + "/../dotfiles/emacs-prod/emacs-common/emacsr";
    executable = true;
  };

  # desktop entry (goes under ~/.local/share/applications)
  xdg.desktopEntries."emacs-prod" = {
    name = "Emacs (prod)";
    comment = "Emacs daemon client (prod)";
    exec = "${emacsPkg}/bin/emacsclient -c -s prod %u";
    terminal = false;
    type = "Application";
    categories = [ "Development" "TextEditor" ];
  };

  # user service: emacs-prod (daemon)
  systemd.user.services."emacs-prod" = {
    Unit = {
      Description = "Emacs daemon (prod)";
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${emacsPkg}/bin/emacs --fg-daemon=prod";
      ExecStop  = "${emacsPkg}/bin/emacsclient --eval (kill-emacs)";
      Restart   = "on-failure";
      Type      = "simple";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # tangle literate config on each activation (keeps your flow)
  home.activation.tangleEmacsProd =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      set -euo pipefail
      src="${config.xdg.configHome}/emacs-prod/emacs_babel_config/emacs_config.org"
      dst="${config.xdg.configHome}/emacs-prod/modules"
      mkdir -p "$dst"
      if [ -f "$src" ]; then
        ${emacsBatch}/bin/emacs --batch \
          --eval "(progn (require 'org) (org-babel-tangle-file \"$src\"))"
      fi
    '';

  # optional niceties
  programs.emacs = {
    enable = true;
    package = emacsPkg;
  };
  services.emacs.enable = false; # we use emacs-prod instead
}
