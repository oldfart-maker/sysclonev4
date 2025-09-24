#!/usr/bin/env bash
set -euo pipefail
# Adjust this user if your default user isn't literally "username"
USER_NAME="username"
if id "$USER_NAME" &>/dev/null; then
  chown -R "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.config" 2>/dev/null || true
fi
install -d -m 0755 /var/lib/sysclone
touch /var/lib/sysclone/.fix-ownership-done
