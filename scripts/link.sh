#!/usr/bin/env bash
# Links config files from this repo into $HOME, through ~/.dotfiles.
# Safe to re-run: existing links are replaced, real files are backed up first.
set -euo pipefail

DOT="$HOME/.dotfiles"
STAMP="$(date +%Y%m%d-%H%M%S)"

# target in $HOME  ->  source under ~/.dotfiles
LINKS=(
  ".zshrc                       home/.zshrc"
  ".zshenv                      home/.zshenv"
  ".config/starship.toml        home/.config/starship.toml"
  ".config/nvim                 home/.config/nvim"
  ".config/herdr                home/.config/herdr"
  ".codex/AGENTS.md             home/AGENTS.md"
  ".config/opencode/AGENTS.md   home/AGENTS.md"
)

link() {
  local target="$HOME/$1" src="$DOT/$2"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$target.pre-dotfiles-wsl.$STAMP"
    echo "    backed up $1 to $1.pre-dotfiles-wsl.$STAMP"
  fi
  ln -sfn "$src" "$target"
  echo "    ~/$1 -> ~/.dotfiles/$2"
}

for entry in "${LINKS[@]}"; do
  # shellcheck disable=SC2086
  link $entry
done

# Leftovers from home-manager that point into /nix/store and would dangle once Nix is gone.
for stale in "$HOME/.zprofile" "$HOME/.config/direnv/lib/hm-nix-direnv.sh"; do
  if [ -L "$stale" ] && [[ "$(readlink "$stale")" == /nix/store/* ]]; then
    rm "$stale"
    echo "    removed ${stale/#$HOME/~} (home-manager link into /nix/store)"
  fi
done
