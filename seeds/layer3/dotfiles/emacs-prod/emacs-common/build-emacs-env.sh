#!/usr/bin/env bash
set -euo pipefail

echo "==> Creating required directories..."
mkdir -p \
  ~/.config/emacs-common \
  ~/.config/systemd/user \
  ~/.config/emacs-prod/modules \
  ~/.local/bin

echo "==> Cloning emacs_babel_config..."
git clone https://github.com/oldfart-maker/emacs_babel_config.git /tmp/emacs_babel_config

echo "==> Running Emacs to tangle config..."
emacs --batch --chdir=/tmp/emacs_babel_config \
  --eval="(progn
             (require 'org)
             (org-babel-tangle-file \"emacs_config.org\"))"

echo "==> Copying tangled modules to emacs-prod..."
cp -r /tmp/emacs_babel_config/modules/* ~/.config/emacs-prod/modules/

echo "==> Sparse-checkout of emacs-common from lenovo-dotfiles..."
rm -rf /tmp/lenovo-dotfiles
git clone --filter=blob:none --no-checkout https://github.com/oldfart-maker/lenovo-dotfiles.git /tmp/lenovo-dotfiles
git -C /tmp/lenovo-dotfiles sparse-checkout init --cone
git -C /tmp/lenovo-dotfiles sparse-checkout set .config/emacs-common
git -C /tmp/lenovo-dotfiles checkout

echo "==> Copying emacs-common files..."
cp /tmp/lenovo-dotfiles/.config/emacs-common/emacs-prod.service ~/.config/systemd/user/
sudo cp /tmp/lenovo-dotfiles/.config/emacs-common/emacs-prod.desktop /usr/share/applications/
cp /tmp/lenovo-dotfiles/.config/emacs-common/emacs-profile ~/.local/bin/
cp /tmp/lenovo-dotfiles/.config/emacs-common/emacsr ~/.local/bin/

echo "==> Registering and starting emacs-prod.service..."
systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable --now emacs-prod.service

echo "✅ Emacs environment setup complete!"
