#!/usr/bin/env bash
# Re-apply the config after any edit. No sudo: home-manager only writes $HOME.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
exec home-manager switch --flake ~/.dotfiles#wsl -b backup
