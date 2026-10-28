#!/usr/bin/env bash
# Takes a fresh WSL Ubuntu to the full setup: apt packages, vendor CLIs, pinned
# downloads, linked config, zsh as the login shell, the font and terminal theme
# on the Windows side.
#
# Safe to re-run at any time: every step checks before it acts. Re-running is
# also how a new entry in packages/ gets installed.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=packages/pinned.sh
. "$DIR/packages/pinned.sh"
BIN="$HOME/.local/bin"
OPT="$HOME/.local/opt"
mkdir -p "$BIN" "$OPT"

# Download $1 to $3 and refuse to continue unless its SHA-256 is $2.
fetch() {
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --quiet - || { echo "    checksum mismatch for $1" >&2; exit 1; }
}

echo "==> Step 0: confirm we are inside WSL"
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "    This does not look like WSL. Linux steps still work; the Windows ones (7, 8) will not."
fi

echo "==> Step 1: apt packages (needs sudo)"
# shellcheck source=/dev/null
. /etc/os-release
sudo apt-get update -qq
sudo apt-get install -y -qq curl ca-certificates gnupg
sudo install -d -m 755 /etc/apt/keyrings

# Vendor repos for the three packages Ubuntu ships too old or not at all.
# Their versions are higher than Ubuntu's, so apt prefers them without pinning.
if [ ! -f /etc/apt/sources.list.d/github-cli.list ]; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
fi
if [ ! -f /etc/apt/sources.list.d/hashicorp.list ]; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | sudo gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${VERSION_CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
fi
if [ ! -f /etc/apt/sources.list.d/nodesource.list ]; then
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | sudo gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
    | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
fi

mapfile -t APT_PACKAGES < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$DIR/packages/apt.txt")
sudo apt-get update -qq
sudo apt-get install -y -qq "${APT_PACKAGES[@]}"

echo "==> Step 2: vendor CLIs"
# Databricks CLI: the official installer puts it in /usr/local/bin and exits
# if a copy is already there, so only run it when missing. update.sh upgrades.
if [ -x /usr/local/bin/databricks ]; then
  echo "    databricks already installed ($(/usr/local/bin/databricks --version))"
else
  curl -fsSL https://raw.githubusercontent.com/databricks/setup-cli/main/install.sh | sudo sh
fi
# uv: the official installer, told not to edit shell files (home/.zshenv puts
# ~/.local/bin on PATH already).
if [ -x "$BIN/uv" ]; then
  echo "    uv already installed ($("$BIN/uv" --version))"
else
  curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
fi

echo "==> Step 3: language servers and pinned downloads"
# npm globals go to ~/.local, so they need no sudo and land in ~/.local/bin.
npm config set prefix "$HOME/.local"
# shellcheck disable=SC2086
npm install -g --silent $NPM_GLOBALS
for tool in $UV_TOOLS; do
  "$BIN/uv" tool install --quiet "$tool" 2>/dev/null || "$BIN/uv" tool upgrade --quiet "$tool"
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ ! -x "$OPT/herdr-$HERDR_VERSION/herdr" ]; then
  fetch "$HERDR_URL" "$HERDR_SHA256" "$TMP/herdr"
  install -Dm755 "$TMP/herdr" "$OPT/herdr-$HERDR_VERSION/herdr"
fi
ln -sfn "$OPT/herdr-$HERDR_VERSION/herdr" "$BIN/herdr"
echo "    herdr $HERDR_VERSION"

if [ ! -x "$OPT/lua-language-server-$LUALS_VERSION/bin/lua-language-server" ]; then
  fetch "$LUALS_URL" "$LUALS_SHA256" "$TMP/luals.tar.gz"
  mkdir -p "$OPT/lua-language-server-$LUALS_VERSION"
  tar -xzf "$TMP/luals.tar.gz" -C "$OPT/lua-language-server-$LUALS_VERSION"
fi
# A wrapper rather than a symlink: lua-language-server finds its runtime files
# relative to the path it was started from.
printf '#!/bin/sh\nexec "%s" "$@"\n' "$OPT/lua-language-server-$LUALS_VERSION/bin/lua-language-server" > "$BIN/lua-language-server"
chmod +x "$BIN/lua-language-server"
echo "    lua-language-server $LUALS_VERSION"

FONT_DIR="$HOME/.local/share/fonts/HackNerdFont"
if [ "$(cat "$FONT_DIR/.version" 2>/dev/null)" != "$NERDFONT_VERSION" ]; then
  fetch "$NERDFONT_URL" "$NERDFONT_SHA256" "$TMP/hack.tar.xz"
  rm -rf "$FONT_DIR" && mkdir -p "$FONT_DIR"
  tar -xJf "$TMP/hack.tar.xz" -C "$FONT_DIR" --wildcards '*.ttf'
  echo "$NERDFONT_VERSION" > "$FONT_DIR/.version"
  fc-cache -f "$FONT_DIR" >/dev/null
fi
echo "    Hack Nerd Font $NERDFONT_VERSION"

# Debian calls fd's binary fdfind; give it its usual name.
ln -sfn /usr/bin/fdfind "$BIN/fd"

# git asks gh for GitHub credentials through an absolute path to gh. Re-point it at
# the apt gh, or a helper left over from an old install breaks every https push.
if gh auth status >/dev/null 2>&1; then
  gh auth setup-git
  echo "    git credential helper -> $(command -v gh)"
fi

echo "==> Step 4: link config into \$HOME"
# Every link goes through ~/.dotfiles, so the repo folder can move or be renamed.
ln -sfn "$DIR" "$HOME/.dotfiles"
"$DIR/scripts/link.sh"

echo "==> Step 5: remove the old Nix lines from bash's startup files"
# The Nix-based setup appended PATH blocks to ~/.profile and ~/.bashrc, and a
# block that launches the Nix zsh. Each starts with a "# dotfiles-wsl:" marker.
strip_block() {  # file, regex for the block's first line, regex for its last line
  [ -f "$1" ] && grep -qE "$2" "$1" || return 0
  cp -f "$1" "$1.pre-drop-nix"
  awk -v s="$2" -v e="$3" '$0 ~ s {skip=1} !skip {print} skip && $0 ~ e {skip=0}' "$1.pre-drop-nix" > "$1"
  echo "    cleaned ${1/#$HOME/~} (backup: ${1/#$HOME/~}.pre-drop-nix)"
}
strip_block "$HOME/.profile" '^# dotfiles-wsl: let Nix win the PATH' '^export PATH=.*nix-profile/bin'
strip_block "$HOME/.bashrc"  '^# dotfiles-wsl: let Nix win the PATH' '^export PATH=.*nix-profile/bin'
strip_block "$HOME/.bashrc"  '^# dotfiles-wsl: launch zsh'           '^fi$'

echo "==> Step 6: make zsh the login shell"
ZSH_BIN="/usr/bin/zsh"
# The Nix setup registered its own zsh here; that path stops existing with Nix.
if grep -q 'nix-profile' /etc/shells; then
  sudo sed -i '\|nix-profile|d' /etc/shells
  echo "    removed the Nix zsh from /etc/shells"
fi
if [ "$(getent passwd "$USER" | cut -d: -f7)" = "$ZSH_BIN" ]; then
  echo "    already the login shell"
elif chsh -s "$ZSH_BIN"; then
  echo "    login shell is now $ZSH_BIN (applies to new terminals)"
else
  # chsh needs your UNIX password and fails under some WSL PAM setups.
  # Fallback: a login bash hands over to zsh.
  echo "    chsh failed; launching zsh from ~/.bashrc instead."
  cat >> "$HOME/.bashrc" <<'BASHRC'

# dotfiles-wsl: launch zsh -- remove this block once `chsh` is working
# Guards: only a LOGIN, interactive shell on a real tty, never recursively,
# so tooling that runs `bash -ic "cmd"` is not hijacked.
if shopt -q login_shell && [[ $- == *i* ]] && [ -t 0 ] \
   && [ -z "${ZSH_VERSION:-}" ] && [ -x /usr/bin/zsh ]; then
  exec /usr/bin/zsh -l
fi
BASHRC
fi

echo "==> Step 7: the font on the Windows side"
"$DIR/scripts/install-windows-font.sh" || \
  echo "    Font install failed; run ./scripts/install-windows-font.sh later."

echo "==> Step 8: seed the Windows Terminal theme (first install only)"
# Seeding once gives a new machine your look; reasserting it on every run would
# fight Windows Terminal's own Settings UI. The script is a no-op if the scheme
# is already there.
if [ -n "${DOTFILES_SKIP_THEME:-}" ]; then
  echo "    DOTFILES_SKIP_THEME is set, leaving Windows Terminal alone."
else
  "$DIR/scripts/apply-windows-terminal-theme.sh" || \
    echo "    Theme not applied; run ./scripts/apply-windows-terminal-theme.sh later."
fi

cat <<'NEXT'

==> Done.

Open a new terminal to get zsh with the new setup. If glyphs look wrong,
restart Windows Terminal, or sign out of Windows and back in once.
Check everything with: ./scripts/check-drift.sh
NEXT
