#!/usr/bin/env bash
# Install the terminal font on the Windows side from inside WSL. No PowerShell
# step, no admin rights.
#
# Only the font crosses the WSL/Windows boundary. It has to, because Windows
# draws the glyphs and cannot see Linux fontconfig - and sourcing it from the
# Nix store means the font version is pinned by flake.lock like everything else.
#
# Colours, opacity, padding and the background image are deliberately NOT
# synced. Windows Terminal's settings.json is a file you edit through its own
# UI, and every setting in it is a matter of taste. A repo that overwrites it on
# every rebuild fights the user for control of their own terminal. Same rule as
# ~/.claude in home.nix: only manage what this repo owns outright.
#
# Idempotent: re-running changes nothing new.
# Called automatically by bootstrap.sh and rebuild.sh. Safe to run by hand.
set -euo pipefail

# The font comes from the home-manager profile. When bootstrap.sh calls this,
# the calling shell was started before the first switch ever ran, so the profile
# is not on PATH yet. Put it there rather than depending on the caller.
export PATH="$HOME/.nix-profile/bin:$PATH"

info() { printf '    %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }

# --- preconditions ----------------------------------------------------------
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  info "not running under WSL, nothing to sync"
  exit 0
fi

# Windows interop must actually be available. Without it the lookups below
# fail quietly and we would compute a nonsense destination.
for bin in cmd.exe reg.exe wslpath; do
  command -v "$bin" >/dev/null 2>&1 || {
    warn "$bin not found; Windows interop is unavailable in this shell"
    exit 1
  }
done

# The Windows user profile directory, asked of Windows rather than guessed:
# the Windows and WSL usernames are frequently different.
WIN_HOME_RAW="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r' || true)"
# Must look like "C:\Users\name". Guarding here matters: `wslpath ""` returns
# "." with exit status 0, which would silently target the current directory.
case "$WIN_HOME_RAW" in
  [A-Za-z]:\\*) : ;;
  *) warn "could not read %USERPROFILE% from Windows (got: '${WIN_HOME_RAW:-empty}')"
     exit 1 ;;
esac

WIN_HOME="$(wslpath -u "$WIN_HOME_RAW" 2>/dev/null || true)"
case "$WIN_HOME" in
  /*) : ;;
  *) warn "wslpath could not convert '$WIN_HOME_RAW'"; exit 1 ;;
esac
if [ ! -d "$WIN_HOME" ]; then
  warn "the Windows user profile directory does not exist: $WIN_HOME"
  exit 1
fi

# --- 1. the font ------------------------------------------------------------
# Sourced from the Nix store, so the font version is pinned by flake.lock
# rather than by whatever a download URL happens to serve today.
install_font() {
  local src_dir dest_dir face src dest changed=0
  src_dir="$(dirname "$(readlink -f "$HOME/.nix-profile/share/fonts/truetype/NerdFonts/Hack/HackNerdFont-Regular.ttf" 2>/dev/null || true)")"
  if [ ! -d "$src_dir" ]; then
    warn "Hack Nerd Font not in the Nix profile; is nerd-fonts.hack in home.packages?"
    return 0
  fi

  dest_dir="$WIN_HOME/AppData/Local/Microsoft/Windows/Fonts"
  mkdir -p "$dest_dir"

  for face in Regular Bold Italic BoldItalic; do
    src="$src_dir/HackNerdFont-$face.ttf"
    dest="$dest_dir/HackNerdFont-$face.ttf"
    [ -f "$src" ] || { warn "missing $face in the Nix package"; continue; }
    if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then
      cp -f "$src" "$dest"
      changed=1
    fi
    # Windows only enumerates a font once it is registered. Per-user fonts live
    # in HKCU and take a full Windows path as their value, so no admin needed.
    local label="Hack Nerd Font (TrueType)"
    [ "$face" = "Regular" ] || label="Hack Nerd Font $face (TrueType)"
    reg.exe add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
      /v "$label" /t REG_SZ \
      /d "$(wslpath -w "$dest")" /f >/dev/null 2>&1 || warn "could not register $face"
  done

  if [ "$changed" -eq 1 ]; then
    info "font installed (sign out and back in if glyphs look wrong)"
  else
    info "font already current"
  fi
}

echo "==> Installing the terminal font on the Windows side"
install_font
