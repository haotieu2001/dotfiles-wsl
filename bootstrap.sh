#!/usr/bin/env bash
# Takes a fresh WSL Ubuntu from nothing to a built home-manager config.
# Run this once. After it finishes, use ./rebuild.sh for every later change.
#
# This is the WSL counterpart of the macOS bootstrap.sh. The big difference:
# there is no nix-darwin and no sudo darwin-rebuild, because WSL Ubuntu is not
# NixOS. home-manager runs standalone and owns only $HOME.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

echo "==> Step 0: confirm we are inside WSL"
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "    This does not look like WSL. On a normal Linux box the rest still"
  echo "    works, but the Windows-side steps at the end will not apply."
fi

echo "==> Step 1: systemd"
# The Determinate installer manages the Nix daemon through systemd. Older WSL
# images boot without an init system, and Nix multi-user mode then has nothing
# to start the daemon with.
if [ -d /run/systemd/system ]; then
  echo "    systemd is running, good"
else
  echo "    systemd is NOT running in this distro."
  if ! grep -q 'systemd *= *true' /etc/wsl.conf 2>/dev/null; then
    echo "    Enabling it in /etc/wsl.conf (needs sudo)..."
    sudo tee -a /etc/wsl.conf >/dev/null <<'WSLCONF'

[boot]
systemd=true
WSLCONF
  fi
  echo ""
  echo "    Now restart WSL from a Windows PowerShell window:"
  echo "        wsl --shutdown"
  echo "    then reopen this distro and re-run ./bootstrap.sh"
  exit 1
fi

echo "==> Step 2: Determinate Nix"
if command -v nix >/dev/null 2>&1; then
  echo "    nix already installed, skipping"
else
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

echo "==> Step 3: symlink this repo to ~/.dotfiles"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 4: personalize the configured username"
REAL_USER="$(whoami)"
FLAKE_USER="$(sed -nE 's/^[[:space:]]*user = "([^"]+)";.*/\1/p' "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
  echo "    Could not find the single \"user = \" line in flake.nix."
  echo "    Edit flake.nix yourself before continuing."
  exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"user = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    # GNU sed: -i takes no argument, unlike the BSD sed the macOS script uses.
    sed -i -E "s/^([[:space:]]*user = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"user = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 5: first home-manager switch"
# home-manager isn't on PATH yet on a fresh machine, so run it straight from
# the flake this once. After this, rebuild.sh works normally.
# -b backup renames any file we are about to take over (~/.bashrc, ~/.profile)
# to <name>.backup instead of aborting the whole activation.
NIX_BIN="$(command -v nix)"

# Retry on transient failure. WSL routes DNS through a proxy on the host
# (usually 10.255.255.254), and it is briefly unreachable while the Nix daemon
# and systemd units settle after Step 2. Fixed-output derivations download
# inside the build sandbox, so they fail with "Could not resolve host" during
# that window even though the flake inputs fetched fine moments earlier.
# Nothing is misconfigured; it just needs another go.
for attempt in 1 2 3; do
  if "$NIX_BIN" run home-manager/release-26.05 -- \
      switch --flake ~/.dotfiles#wsl -b backup; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    echo ""
    echo "    Switch failed three times."
    echo "    If the errors said 'Could not resolve host', check DNS:"
    echo "        curl -sSI https://cache.nixos.org >/dev/null && echo 'DNS ok'"
    echo "    Then re-run ./bootstrap.sh. Already-downloaded packages are cached,"
    echo "    so the retry picks up where this left off."
    exit 1
  fi
  echo "    Attempt $attempt failed, retrying in $((attempt * 15))s (often transient DNS on WSL)..."
  sleep "$((attempt * 15))"
done
# If this fails with "nix: command not found", open a new shell so the Nix
# profile is on PATH, then re-run ./bootstrap.sh.

echo "==> Step 6: make zsh the login shell"
# Ubuntu logs you into bash. The zsh we want is the home-manager one, not an
# apt one, so that the shell is pinned like everything else.
ZSH_BIN="$HOME/.nix-profile/bin/zsh"
if [ ! -x "$ZSH_BIN" ]; then
  echo "    $ZSH_BIN not found, skipping. Re-run after a successful switch."
elif [ "${SHELL:-}" = "$ZSH_BIN" ]; then
  echo "    already the login shell, nothing to do"
else
  # chsh refuses any shell that is not listed in /etc/shells.
  if ! grep -qxF "$ZSH_BIN" /etc/shells 2>/dev/null; then
    echo "    registering $ZSH_BIN in /etc/shells (needs sudo)"
    echo "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
  fi
  # chsh needs your UNIX password (not sudo) and fails under some WSL PAM
  # setups. Fall back to launching zsh from ~/.bashrc, which needs no password.
  if ! chsh -s "$ZSH_BIN"; then
    echo "    chsh failed. Falling back to launching zsh from ~/.bashrc."
    if [ -f "$HOME/.bashrc" ] && grep -q "dotfiles-wsl: launch zsh" "$HOME/.bashrc"; then
      echo "    already present, nothing to do"
    elif [ -L "$HOME/.bashrc" ]; then
      echo "    ~/.bashrc is a symlink (home-manager managed); not touching it."
      echo "    Enable programs.bash in home.nix, or fix chsh, to get zsh at login."
    else
      cp -f "$HOME/.bashrc" "$HOME/.bashrc.pre-dotfiles-wsl" 2>/dev/null || true
      cat >> "$HOME/.bashrc" <<BASHRC

# dotfiles-wsl: launch zsh -- remove this block once \`chsh\` is working
# Guards, in order: only a LOGIN shell, so tooling that runs \`bash -ic "cmd"\`
# is not hijacked and left hanging; only interactive; only on a real tty; and
# never recursively. Dropping the login_shell test breaks any such tooling.
if shopt -q login_shell && [[ \$- == *i* ]] && [ -t 0 ] \\
   && [ -z "\${ZSH_VERSION:-}" ] && [ -x "$ZSH_BIN" ]; then
  exec "$ZSH_BIN" -l
fi
BASHRC
      echo "    added to ~/.bashrc (backup: ~/.bashrc.pre-dotfiles-wsl)"
    fi
  fi
fi

echo "==> Step 7: the font on the Windows side"
# Everything below this point is driven from inside WSL through Windows
# interop, so there is no separate PowerShell step to run.
"$DIR/scripts/install-windows-font.sh" || \
  echo "    Font install failed; run ./scripts/install-windows-font.sh later."

echo "==> Step 8: seed the Windows Terminal theme"
# Only bootstrap does this, never rebuild.sh. Seeding a fresh machine takes
# nothing away from you; reasserting the theme on every rebuild would fight
# Windows Terminal's own Settings UI for ownership of settings.json. The script
# is a no-op if the scheme is already there, so your terminal stays yours.
#
# It is still a one-time overwrite of colours, font and opacity, which someone
# cloning this repo with a terminal they already like will not want. There was
# no way to decline it short of interrupting the install, so:
if [ -n "${DOTFILES_SKIP_THEME:-}" ]; then
  echo "    DOTFILES_SKIP_THEME is set, leaving Windows Terminal alone."
  echo "    Only the font was installed. Apply the theme later if you change"
  echo "    your mind: ./scripts/apply-windows-terminal-theme.sh"
else
  "$DIR/scripts/apply-windows-terminal-theme.sh" || \
    echo "    Theme not applied; run ./scripts/apply-windows-terminal-theme.sh later."
fi

cat <<'NEXT'

==> Done.

Restart Windows Terminal to pick up the font and colour scheme. If glyphs
still look wrong afterwards, sign out of Windows and back in once so the
newly registered font is enumerated.
NEXT

if [ -n "${DOTFILES_SKIP_THEME:-}" ]; then
  cat <<'NEXT'

Your terminal colours were left exactly as they were.
NEXT
else
  cat <<'NEXT'

The theme was seeded once, just now. From here it is yours: change colours,
opacity and padding in Windows Terminal's own Settings UI and nothing in
this repo will overwrite them. The previous settings.json was backed up
next to itself as settings.json.pre-dotfiles-wsl.*
NEXT
fi

cat <<'NEXT'

If you were already in a shell, start a new one so zsh and the Nix
profile are picked up.

From here on, ./rebuild.sh applies every change to packages, shell and
editor in one command.
NEXT
