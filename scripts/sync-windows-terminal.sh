#!/usr/bin/env bash
# Push the terminal look-and-feel from this repo into Windows Terminal,
# driven entirely from inside WSL. No PowerShell step, no admin rights.
#
# Two things cross the WSL/Windows boundary, because Windows draws the pixels:
#   1. the font, copied out of the Nix store and registered per-user
#   2. the colour scheme + profile settings, merged into settings.json
#
# Both are derived from files in this repo, so `git` remains the source of
# truth, and both are idempotent: re-running changes nothing new.
#
# Called automatically by bootstrap.sh and rebuild.sh. Safe to run by hand.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FRAGMENTS="$DIR/home/windows-terminal"

# jq and the font come from the home-manager profile. When bootstrap.sh calls
# this, the calling shell was started before the first switch ever ran, so the
# profile is not on PATH yet. Put it there rather than depending on the caller.
export PATH="$HOME/.nix-profile/bin:$PATH"

info() { printf '    %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }

# --- preconditions ----------------------------------------------------------
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  info "not running under WSL, nothing to sync"
  exit 0
fi
if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found. Run ./rebuild.sh first, then re-run this script."
  exit 1
fi

DISTRO="${WSL_DISTRO_NAME:-}"
if [ -z "$DISTRO" ]; then
  warn "WSL_DISTRO_NAME is unset; cannot tell which profile to patch"
  exit 1
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

# --- 2. the Windows Terminal settings --------------------------------------
sync_settings() {
  local settings
  settings="$(ls -1 \
    "$WIN_HOME"/AppData/Local/Packages/Microsoft.WindowsTerminal*/LocalState/settings.json \
    2>/dev/null | head -n1 || true)"

  if [ -z "$settings" ]; then
    warn "Windows Terminal settings.json not found."
    warn "Launch Windows Terminal once so it writes its config, then re-run."
    return 0
  fi

  # Refuse to touch a file we cannot parse rather than risk clobbering it.
  if ! jq -e . "$settings" >/dev/null 2>&1; then
    warn "settings.json is not valid JSON (comments?); leaving it alone"
    return 0
  fi

  local merged
  merged="$(mktemp)"
  # - schemes: replace ours by name, leave every other scheme untouched
  # - profiles: patch only the profile for this distro, via `*` so existing
  #   keys we do not mention survive
  # - defaultProfile: point at this distro, if we found it
  jq \
    --slurpfile scheme "$FRAGMENTS/rose-pine-moon.json" \
    --slurpfile prof   "$FRAGMENTS/profile.json" \
    --arg distro "$DISTRO" '
    .schemes = ((.schemes // []) | map(select(.name != $scheme[0].name)) + $scheme)
    | .profiles.list = ((.profiles.list // []) | map(
        if .name == $distro then . * $prof[0] else . end))
    | (.profiles.list // []) as $l
    | .defaultProfile = (
        ([$l[] | select(.name == $distro) | .guid] | first) // .defaultProfile)
  ' "$settings" > "$merged"

  if ! jq -e . "$merged" >/dev/null 2>&1; then
    warn "merge produced invalid JSON; original left untouched"
    rm -f "$merged"
    return 1
  fi

  if [ -n "$(jq -e --slurpfile a "$settings" --slurpfile b "$merged" \
        -n 'if $a[0] == $b[0] then empty else 1 end' 2>/dev/null)" ]; then
    cp -f "$settings" "$settings.dotfiles-backup"
    cat "$merged" > "$settings"   # write in place; do not replace the file node
    info "settings merged (backup: settings.json.dotfiles-backup)"
  else
    info "settings already current"
  fi
  rm -f "$merged"

  if ! jq -e --arg d "$DISTRO" '[.profiles.list[]? | select(.name == $d)] | length > 0' \
       "$settings" >/dev/null 2>&1; then
    warn "no Windows Terminal profile named '$DISTRO' yet."
    warn "Open Windows Terminal once so it generates one, then re-run."
  fi
}

echo "==> Syncing Windows Terminal (distro: $DISTRO)"
install_font
sync_settings
