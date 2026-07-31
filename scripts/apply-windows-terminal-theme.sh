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

# The two files the theme is made of. To ship your own, drop your files in
# windows/ and point these at them. The scheme's *name* is read out of the JSON
# rather than written here, so renaming the scheme cannot get out of step with
# the seed-once guard below - which is exactly what used to happen.
SCHEME_FILE="$REPO/windows/blackpanther.json"
IMAGE_FILE="$REPO/windows/blackpanther.jpg"

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

[ -f "$SCHEME_FILE" ] || { warn "no colour scheme at $SCHEME_FILE"; exit 1; }
SCHEME_NAME="$(jq -r '.name // empty' "$SCHEME_FILE" 2>/dev/null || true)"
[ -n "$SCHEME_NAME" ] || { warn "$SCHEME_FILE has no \"name\" field"; exit 1; }

# Windows Terminal matches a profile's colorScheme against a scheme by name, so
# these two files have to agree. If they do not, the merge below writes a
# colorScheme that resolves to nothing and the terminal quietly keeps its old
# colours - a silent failure, same shape as the font-family one.
WANTED_SCHEME="$(jq -r '.colorScheme // empty' "$REPO/windows/profile-defaults.json" 2>/dev/null || true)"
if [ -n "$WANTED_SCHEME" ] && [ "$WANTED_SCHEME" != "$SCHEME_NAME" ]; then
  warn "profile-defaults.json asks for colorScheme \"$WANTED_SCHEME\" but"
  warn "$(basename "$SCHEME_FILE") defines \"$SCHEME_NAME\". Make them match."
  exit 1
fi

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
  warn "Remove them, or apply $(basename "$SCHEME_FILE") by hand. Not touching it."
  exit 0
fi

# --- seed-once guard --------------------------------------------------------
# Look for the scheme *this repo ships*, whatever it is called. Hardcoding
# "blackpanther" here while the merge below took the name from the JSON meant a
# fork that renamed its scheme never tripped this guard, so every bootstrap run
# reasserted the theme over whatever the user had chosen - the precise fight
# this script's header says it exists to avoid.
if [ "$FORCE" -eq 0 ] && \
   jq -e --arg name "$SCHEME_NAME" \
      '.schemes // [] | any(.name == $name)' "$SETTINGS" >/dev/null 2>&1; then
  info "theme already present; leaving your terminal settings alone"
  info "(use --force to overwrite them with the committed theme)"
  exit 0
fi

# --- the background image ---------------------------------------------------
# Copied out of the repo to a stable Windows-side location. Windows Terminal is
# a Windows process, so it needs a real Windows path; pointing it at
# \\wsl.localhost works but is slow to read and breaks if the distro is renamed.
IMG_WIN_PATH=""
if [ -f "$IMAGE_FILE" ]; then
  IMG_NAME="$(basename "$IMAGE_FILE")"
  IMG_DEST_DIR="$WIN_HOME/AppData/Local/dotfiles-wsl"
  mkdir -p "$IMG_DEST_DIR"
  cp -f "$IMAGE_FILE" "$IMG_DEST_DIR/$IMG_NAME"
  IMG_WIN_PATH="$(wslpath -w "$IMG_DEST_DIR/$IMG_NAME")"
else
  warn "$(basename "$IMAGE_FILE") missing; applying the theme without a background"
fi

# --- merge ------------------------------------------------------------------
# $$ disambiguates two runs inside the same second, which would otherwise write
# the same backup name and lose the first one.
BACKUP="$SETTINGS.pre-dotfiles-wsl.$(date +%Y%m%d%H%M%S).$$"
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
  --slurpfile scheme "$SCHEME_FILE" \
  --argjson defaults "$DEFAULTS" \
  '
    .schemes = ((.schemes // []) | map(select(.name != $scheme[0].name)) + [$scheme[0]])
    | .profiles = (.profiles // {})
    | .profiles.defaults = ((.profiles.defaults // {}) * $defaults)
  ' "$SETTINGS" > "$TMP"

# Never leave a half-written settings.json behind: validate before replacing.
jq empty "$TMP" >/dev/null 2>&1 || { warn "merge produced invalid JSON; settings left untouched"; exit 1; }
cp -f "$TMP" "$SETTINGS"

info "applied the $SCHEME_NAME theme (backup: $(basename "$BACKUP"))"
info "Windows Terminal picks this up on its next launch"
