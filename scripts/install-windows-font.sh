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
# Nerd Fonts ships three families per typeface, and the difference matters to a
# terminal. Only the file name distinguishes them:
#
#   HackNerdFont-*.ttf      -> "Hack Nerd Font"       icons are double-width
#   HackNerdFontMono-*.ttf  -> "Hack Nerd Font Mono"  icons squeezed to one cell
#   HackNerdFontPropo-*.ttf -> "Hack Nerd Font Propo" proportional
#
# Windows resolves a font by family *name*, so a profile asking for one family
# gets nothing from another. Map a file name to the registry label Windows
# expects: family, then style, with "Regular" left implicit as Windows does.
font_label() {
  local base="${1%.ttf}" variant style family
  variant="${base%%-*}"                # HackNerdFontMono
  style="${base#*-}"                   # BoldItalic
  variant="${variant#HackNerdFont}"    # "" | Mono | Propo
  family="Hack Nerd Font${variant:+ $variant}"
  case "$style" in
    Regular)    printf '%s (TrueType)\n' "$family" ;;
    BoldItalic) printf '%s Bold Italic (TrueType)\n' "$family" ;;
    *)          printf '%s %s (TrueType)\n' "$family" "$style" ;;
  esac
}

install_font() {
  local src_dir dest_dir src dest name label changed=0 installed=0
  src_dir="$(dirname "$(readlink -f "$HOME/.nix-profile/share/fonts/truetype/NerdFonts/Hack/HackNerdFont-Regular.ttf" 2>/dev/null || true)")"
  if [ ! -d "$src_dir" ]; then
    warn "Hack Nerd Font not in the Nix profile; is nerd-fonts.hack in home.packages?"
    return 0
  fi

  dest_dir="$WIN_HOME/AppData/Local/Microsoft/Windows/Fonts"
  mkdir -p "$dest_dir"

  # Every face the Nix package carries, rather than a hand-written list of four.
  # The list used to name only the four "Hack Nerd Font" faces while
  # windows/profile-defaults.json asked for "Hack Nerd Font Mono", so a fresh
  # machine silently fell back to Cascadia Mono. It went unnoticed because the
  # machine this was written on already had the Mono faces from an earlier
  # install - the same class of bug as the zsh PATH one in home.nix, and only
  # visible on a machine that is not already set up.
  for src in "$src_dir"/*.ttf; do
    [ -f "$src" ] || continue
    name="$(basename "$src")"
    dest="$dest_dir/$name"
    if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then
      cp -f "$src" "$dest"
      changed=1
    fi
    # Windows only enumerates a font once it is registered. Per-user fonts live
    # in HKCU and take a full Windows path as their value, so no admin needed.
    label="$(font_label "$name")"
    if reg.exe add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
         /v "$label" /t REG_SZ \
         /d "$(wslpath -w "$dest")" /f >/dev/null 2>&1; then
      installed=1
    else
      warn "could not register $label"
    fi
  done

  [ "$installed" -eq 1 ] || { warn "no font faces were registered"; return 0; }

  if [ "$changed" -eq 1 ]; then
    info "font installed (sign out and back in if glyphs look wrong)"
  else
    info "font already current"
  fi
}

# The failure above was silent: Windows substitutes a fallback font and the only
# symptom is missing glyphs, which the README blames on needing a sign-out. So
# assert the one thing that has to line up - the family the terminal profile
# asks for is a family we just installed.
check_face_matches() {
  local defaults="$1" face
  command -v jq >/dev/null 2>&1 || return 0        # jq only exists post-switch
  [ -f "$defaults" ] || return 0
  face="$(jq -r '.font.face // empty' "$defaults" 2>/dev/null)"
  [ -n "$face" ] || return 0
  case "$face" in
    "Hack Nerd Font"|"Hack Nerd Font Mono"|"Hack Nerd Font Propo") return 0 ;;
  esac
  warn "windows/profile-defaults.json asks for font \"$face\", which this script"
  warn "does not install. Windows will silently fall back to another font."
}

echo "==> Installing the terminal font on the Windows side"
install_font
check_face_matches "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/windows/profile-defaults.json"
