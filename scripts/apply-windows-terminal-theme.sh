#!/usr/bin/env bash
# Seed Windows Terminal with this repo's colour scheme, font and background,
# from inside WSL. No PowerShell step, no admin rights.
#
# THIS RUNS ONCE, FROM bootstrap.sh. It is deliberately NOT called by
# rebuild.sh.
#
# The distinction matters and is the whole design of this script. Windows
# Terminal's settings.json is a file Windows Terminal itself writes every time
# you touch its Settings UI. A repo that reasserts its own values on every
# rebuild is in a permanent fight with the application for ownership of that
# file, and whoever ran last wins. An earlier version of this repo did exactly
# that; it was removed for good reason.
#
# Seeding a *fresh machine* is a different operation. A new Windows install has
# no scheme of yours in it, so writing one takes nothing away, and afterwards
# ownership passes to you permanently: this script will not touch a settings
# file that already has the scheme in it.
#
# So the rule is: seed once, then hand off. Re-running is a no-op. Use --force
# only if you deliberately want to overwrite your current terminal look with
# the committed one.
#
# Safe to run by hand. Backs up settings.json before its single write.
set -euo pipefail

# jq comes from the home-manager profile. bootstrap.sh calls this from a shell
# that started before the first switch, so the profile is not on PATH yet.
export PATH="$HOME/.nix-profile/bin:$PATH"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

info() { printf '    %s\n' "$*"; }
warn() { printf '    ! %s\n' "$*" >&2; }

# --- preconditions ----------------------------------------------------------
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  info "not running under WSL, nothing to theme"
  exit 0
fi

for bin in cmd.exe wslpath jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    warn "$bin not found; cannot apply the terminal theme"
    exit 1
  }
done

# Ask Windows for its user profile rather than guessing: the Windows and WSL
# usernames are frequently different.
WIN_HOME_RAW="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r' || true)"
# `wslpath ""` returns "." with status 0, which would silently target the
# current directory, so the shape of this value has to be checked first.
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
[ -d "$WIN_HOME" ] || { warn "no such Windows profile directory: $WIN_HOME"; exit 1; }

# --- locate settings.json ---------------------------------------------------
# Windows Terminal ships in three flavours and each keeps its settings
# somewhere different. Stable Store build first, since that is what Windows 11
# preinstalls.
find_settings() {
  local base="$WIN_HOME/AppData/Local" p
  for p in \
    "$base/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json" \
    "$base/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json" \
    "$base/Microsoft/Windows Terminal/settings.json"
  do
    [ -f "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  return 1
}

SETTINGS="$(find_settings || true)"
if [ -z "$SETTINGS" ]; then
  warn "Windows Terminal settings.json not found."
  warn "Launch Windows Terminal once so it writes its config, then re-run:"
  warn "  ./scripts/apply-windows-terminal-theme.sh"
  exit 0
fi

# Windows Terminal writes JSONC: comments and trailing commas are legal there
# but not in jq. A hand-edited file can therefore be unparseable here even
# though the terminal reads it fine. Bail out rather than mangle it.
if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
  warn "settings.json is not strict JSON (comments or trailing commas?)."
  warn "Remove them, or apply windows/blackpanther.json by hand. Not touching it."
  exit 0
fi

# --- seed-once guard --------------------------------------------------------
if [ "$FORCE" -eq 0 ] && \
   jq -e '.schemes // [] | any(.name == "blackpanther")' "$SETTINGS" >/dev/null 2>&1; then
  info "theme already present; leaving your terminal settings alone"
  info "(use --force to overwrite them with the committed theme)"
  exit 0
fi

# --- the background image ---------------------------------------------------
# Copied out of the repo to a stable Windows-side location. Windows Terminal is
# a Windows process, so it needs a real Windows path; pointing it at
# \\wsl.localhost works but is slow to read and breaks if the distro is renamed.
IMG_SRC="$REPO/windows/blackpanther.jpg"
IMG_WIN_PATH=""
if [ -f "$IMG_SRC" ]; then
  IMG_DEST_DIR="$WIN_HOME/AppData/Local/dotfiles-wsl"
  mkdir -p "$IMG_DEST_DIR"
  cp -f "$IMG_SRC" "$IMG_DEST_DIR/blackpanther.jpg"
  IMG_WIN_PATH="$(wslpath -w "$IMG_DEST_DIR/blackpanther.jpg")"
else
  warn "windows/blackpanther.jpg missing; applying the theme without a background"
fi

# --- merge ------------------------------------------------------------------
BACKUP="$SETTINGS.pre-dotfiles-wsl.$(date +%Y%m%d%H%M%S)"
cp -f "$SETTINGS" "$BACKUP"

# Build the defaults we are about to merge, substituting the real image path
# (or dropping the three background keys entirely if we have no image).
DEFAULTS="$(
  if [ -n "$IMG_WIN_PATH" ]; then
    jq --arg img "$IMG_WIN_PATH" '.backgroundImage = $img' "$REPO/windows/profile-defaults.json"
  else
    jq 'del(.backgroundImage, .backgroundImageOpacity, .backgroundImageStretchMode)' \
      "$REPO/windows/profile-defaults.json"
  fi
)"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Two merges, both additive:
#   schemes  - drop any same-named scheme, then append ours, so re-running with
#              --force updates in place instead of accumulating duplicates.
#   defaults - `*` recursive-merges, so keys we do not mention (startingDirectory,
#              your own tweaks) survive untouched.
jq \
  --slurpfile scheme "$REPO/windows/blackpanther.json" \
  --argjson defaults "$DEFAULTS" \
  '
    .schemes = ((.schemes // []) | map(select(.name != $scheme[0].name)) + [$scheme[0]])
    | .profiles = (.profiles // {})
    | .profiles.defaults = ((.profiles.defaults // {}) * $defaults)
  ' "$SETTINGS" > "$TMP"

# Never leave a half-written settings.json behind: validate before replacing.
jq empty "$TMP" >/dev/null 2>&1 || { warn "merge produced invalid JSON; settings left untouched"; exit 1; }
cp -f "$TMP" "$SETTINGS"

info "applied the blackpanther theme (backup: $(basename "$BACKUP"))"
info "Windows Terminal picks this up on its next launch"
