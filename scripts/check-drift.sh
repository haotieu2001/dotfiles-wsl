#!/usr/bin/env bash
# Read-only check that this machine matches the repo:
#   1. every tool bootstrap.sh installs is present and comes from where it should,
#   2. nothing undeclared sits in ~/.local/bin, where it could shadow apt,
#   3. no Nix is left behind.
# Exit 1 means something needs fixing; notes alone do not fail.
set -uo pipefail

bad=0
ok()      { printf '  ok    %s\n' "$*"; }
problem() { printf '  FIX   %s\n' "$*"; bad=1; }
note()    { printf '  note  %s\n' "$*"; }
section() { printf '\n== %s\n' "$*"; }

expect() {  # command, expected directory
  local path
  path="$(command -v "$1" 2>/dev/null)" || { problem "$1 is not installed (re-run ./bootstrap.sh)"; return; }
  if [ "$(dirname "$path")" = "$2" ]; then
    ok "$1 -> $path"
  else
    problem "$1 resolves to $path, expected $2/$1 (something earlier on PATH is winning)"
  fi
}

section "apt (/usr/bin)"
for t in zsh git gh rg fdfind fzf jq lazygit tree nvim make psql node npm terraform starship direnv; do
  expect "$t" /usr/bin
done

section "vendor installers and pinned downloads"
expect databricks /usr/local/bin
for t in uv herdr lua-language-server fd basedpyright typescript-language-server bash-language-server; do
  expect "$t" "$HOME/.local/bin"
done

section "anything else in ~/.local/bin"
known=" uv uvx herdr lua-language-server fd basedpyright basedpyright-langserver typescript-language-server tsc tsserver bash-language-server claude aws aws_completer "
extra=0
for f in "$HOME"/.local/bin/*; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  case "$known" in *" $b "*) ;; *) note "$b is not declared by this repo"; extra=1 ;; esac
done
[ "$extra" -eq 0 ] && ok "only declared tools (plus claude and aws, which update themselves)"

section "Nix leftovers"
left=0
for p in /nix "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.local/state/nix" "$HOME/.local/state/home-manager"; do
  [ -e "$p" ] && { problem "$p still exists"; left=1; }
done
grep -q nix-profile /etc/shells 2>/dev/null && { problem "/etc/shells still lists a Nix zsh"; left=1; }
grep -qs 'nix-profile' "$HOME/.profile" "$HOME/.bashrc" && { problem "~/.profile or ~/.bashrc still mentions nix-profile"; left=1; }
case ":$PATH:" in *nix*) problem "PATH still contains a Nix directory"; left=1 ;; esac
grep -qs 'nix-profile' "$HOME/.gitconfig" && { problem "~/.gitconfig still calls a Nix binary (run: gh auth setup-git)"; left=1; }
for f in "$HOME/.zshrc" "$HOME/.zshenv" "$HOME/.zprofile" "$HOME/.config/starship.toml" "$HOME/.config/nvim"; do
  [ -L "$f" ] && [[ "$(readlink "$f")" == /nix/store/* ]] && { problem "${f/#$HOME/~} still links into /nix/store"; left=1; }
done
[ "$left" -eq 0 ] && ok "none"

section "login shell"
shell="$(getent passwd "$USER" | cut -d: -f7)"
if [ "$shell" = /usr/bin/zsh ]; then ok "zsh"
elif grep -qs 'dotfiles-wsl: launch zsh' "$HOME/.bashrc"; then note "bash, handing over to zsh from ~/.bashrc (chsh failed)"
else problem "login shell is $shell; re-run ./bootstrap.sh"
fi

echo
[ "$bad" -eq 0 ] && echo "All good." || echo "Some items need fixing (FIX above)."
exit "$bad"
