#!/usr/bin/env bash
# Re-apply the config after any edit. No sudo: home-manager only writes $HOME.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# home-manager shells out to `nix`. A login shell gets it from
# /etc/profile.d/nix.sh, but a cron job, a script, or an agent session may not,
# so source the daemon profile if it is missing rather than failing obscurely.
if ! command -v nix >/dev/null 2>&1 && [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

ln -sfn "$DIR" ~/.dotfiles
home-manager switch --flake ~/.dotfiles#wsl -b backup

# Push the terminal font + colours to the Windows side. Cheap and idempotent,
# so it runs every time and cannot drift from what is committed here.
exec "$DIR/scripts/install-windows-font.sh"
