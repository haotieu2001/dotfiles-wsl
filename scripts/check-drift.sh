#!/usr/bin/env bash
# Report where this machine has drifted away from what the repo declares.
#
# The point of this repo is that a new laptop ends up identical to this one by
# running bootstrap.sh. Anything installed some other way - `curl | sh` into
# ~/.local/bin, a version manager like nvm or fnm, `apt install` - breaks that
# promise in a way nothing else notices:
#
#   - It is not in flake.lock, so it is not pinned and not reproducible.
#   - It will not exist on the new laptop, so whatever depends on it breaks
#     there and not here, which is the worst place to find out.
#   - Worse, if it sits earlier on PATH than ~/.nix-profile/bin, it silently
#     wins over the copy this repo declares. `home.packages` then lists a tool
#     you are not actually running.
#
# That last case is the dangerous one, because everything looks fine. home.nix
# says nodejs_24, the build says nodejs_24, and `node --version` answers from
# nvm. This script exists to make that visible.
#
# Read-only. It changes nothing, it only reports. Run it whenever you want, and
# especially before trusting this repo to rebuild a new machine.
#
# Exit status:
#   0   no drift
#   1   drift found (so it is usable from CI or a git hook if you ever want it)
#
# Every "~" below is inside a message printed for a human to read, never a path
# the script opens. Expanding them would print your full home directory on
# every line for no gain.
# shellcheck disable=SC2088
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Same reason as rebuild.sh: `nix` comes from the daemon profile, which a login
# shell picks up but a script, cron job or agent session may not have.
if ! command -v nix >/dev/null 2>&1 && [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

drift=0

# Colour only when writing to a terminal, so redirecting to a file or piping
# into a CI log does not fill it with escape sequences.
if [ -t 1 ]; then
  B=$'\033[1m'; R=$'\033[31m'; Y=$'\033[33m'; G=$'\033[32m'; Z=$'\033[0m'
else
  B=''; R=''; Y=''; G=''; Z=''
fi

section() { printf '\n%s== %s%s\n' "$B" "$*" "$Z"; }
bad()     { printf '  %sx%s %s\n' "$R" "$Z" "$*"; drift=1; }
warn()    { printf '  %s!%s %s\n' "$Y" "$Z" "$*"; }
ok()      { printf '  %sok%s %s\n' "$G" "$Z" "$*"; }
note()    { printf '      %s\n' "$*"; }

# Is a path provided by Nix? Resolve it first: ~/.nix-profile/bin/rg is a
# symlink chain that ends inside /nix/store.
from_nix() {
  case "$(readlink -f "$1" 2>/dev/null)" in
    /nix/store/*) return 0 ;;
    *)            return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# 1. Declared tools that are not the ones you actually run.
#
# The list of declared binaries is taken from the *built* config rather than by
# reading home.nix as text. That catches a case text-parsing cannot: a tool you
# added to home.nix but never rebuilt, which is declared and yet absent.
section "Declared tools vs what actually runs"

echo "  building the declared config (cached after the first run)..."
build_log="$(mktemp)"
trap 'rm -f "$build_log"' EXIT
if ! GEN="$(nix build --no-link --print-out-paths --no-warn-dirty \
             "$DIR#homeConfigurations.wsl.activationPackage" 2>"$build_log")"; then
  bad "could not build homeConfigurations.wsl - fix that before trusting this report"
  sed 's/^/      /' "$build_log" >&2
  GEN=""
fi

if [ -n "$GEN" ]; then
  declared_bin="$GEN/home-path/bin"
  missing=0
  shadowed=0

  for path in "$declared_bin"/*; do
    name="$(basename "$path")"
    # `command -v` uses this script's PATH, inherited from the shell that ran
    # it. That is deliberate: we want to know what *you* get when you type the
    # name, not what some idealised PATH would give.
    actual="$(command -v "$name" 2>/dev/null || true)"

    if [ -z "$actual" ]; then
      # Declared and built, but not on PATH at all. Almost always a stale
      # profile: home.nix gained a package and nobody ran ./rebuild.sh.
      bad "$name is declared but not installed"
      missing=$((missing + 1))
    elif ! from_nix "$actual"; then
      bad "$name resolves to $actual"
      note "not the Nix copy; something earlier on PATH is winning"
      shadowed=$((shadowed + 1))
    fi
  done

  if [ "$missing" -gt 0 ]; then
    echo
    note "$missing declared tool(s) are not installed. Run ./rebuild.sh."
  fi
  if [ "$shadowed" -gt 0 ]; then
    echo
    note "$shadowed declared tool(s) are shadowed. Removing the non-Nix copy"
    note "or the PATH entry ahead of ~/.nix-profile/bin fixes this."
  fi
  [ "$missing" -eq 0 ] && [ "$shadowed" -eq 0 ] && ok "every declared tool resolves to the Nix store"
fi

# ---------------------------------------------------------------------------
# 2. Installers that put software somewhere Nix does not manage.
#
# These are latent rather than broken: they may not be shadowing anything
# today, but they are not in flake.lock and will not exist on a new machine.
section "Non-Nix installers in \$HOME"

found_installer=0

# dir:what installed it
for entry in \
  ".nvm:nvm (node version manager)" \
  ".local/share/fnm:fnm (node version manager)" \
  ".pyenv:pyenv (python version manager)" \
  ".rbenv:rbenv (ruby version manager)" \
  ".cargo:rustup/cargo" \
  ".rustup:rustup" \
  ".bun:bun installer" \
  ".deno:deno installer" \
  ".volta:volta" \
  ".sdkman:sdkman" \
  ".asdf:asdf" \
  "go:go toolchain"
do
  d="${entry%%:*}"
  what="${entry#*:}"
  if [ -e "$HOME/$d" ]; then
    size="$(du -sh "$HOME/$d" 2>/dev/null | cut -f1 || echo '?')"
    warn "~/$d ($size) - $what"
    found_installer=1
  fi
done

# ~/.local/bin is the standard target for `curl ... | sh` and for
# `pip install --user`, so it gets its own pass. Some of what lands here is
# deliberate, so this reports rather than condemns.
if [ -d "$HOME/.local/bin" ]; then
  found_installer=1
  warn "~/.local/bin ($(du -sh "$HOME/.local/bin" 2>/dev/null | cut -f1)) - curl installers and pip --user"
  for f in "$HOME/.local/bin"/*; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    case "$b" in
      # Deliberate exception, documented in home.nix: claude-code ships a
      # self-updater, and pinning it in the read-only store freezes it.
      claude|claude-code) note "$b (deliberate, see home.nix)" ;;
      *)                  note "$b" ;;
    esac
  done
fi

[ "$found_installer" -eq 0 ] && ok "none found"

# ---------------------------------------------------------------------------
# 3. PATH order.
#
# This is the root cause of every "shadowed" line in section 1. A directory
# ahead of ~/.nix-profile/bin wins for any name it contains.
section "PATH entries ahead of the Nix profile"

nix_pos=0
i=0
IFS=':' read -r -a path_dirs <<< "$PATH"
for d in "${path_dirs[@]}"; do
  i=$((i + 1))
  case "$d" in
    "$HOME/.nix-profile/bin") nix_pos=$i; break ;;
  esac
done

if [ "$nix_pos" -eq 0 ]; then
  bad "~/.nix-profile/bin is not on PATH at all"
  note "nothing this repo installs is reachable; open a new shell or run ./rebuild.sh"
else
  found_ahead=0
  i=0
  for d in "${path_dirs[@]}"; do
    i=$((i + 1))
    [ "$i" -ge "$nix_pos" ] && break
    case "$d" in
      # The OS's own directories and the Windows interop paths are expected to
      # be there and are not drift.
      /usr/local/sbin|/usr/local/bin|/usr/sbin|/usr/bin|/sbin|/bin) ;;
      /usr/games|/usr/local/games|/snap/bin|/usr/lib/wsl/lib|/mnt/*) ;;
      /nix/*) ;;
      *)
        bad "$d comes before ~/.nix-profile/bin"
        found_ahead=1
        ;;
    esac
  done
  [ "$found_ahead" -eq 0 ] && ok "nothing unexpected is ahead of ~/.nix-profile/bin"
fi

# ---------------------------------------------------------------------------
# 4. apt packages that duplicate a declared one.
#
# git and curl are excluded on purpose: bootstrap.sh needs both before Nix
# exists, so the apt copies are load-bearing and not drift.
section "apt packages that Nix also provides"

apt_dupes=0
if command -v dpkg-query >/dev/null 2>&1; then
  for p in ripgrep fd-find fzf jq lazygit neovim gh direnv zsh nodejs npm golang rustc; do
    if [ "$(dpkg-query -W -f='${Status}' "$p" 2>/dev/null || true)" = "install ok installed" ]; then
      warn "apt has $p, which home.nix also declares"
      apt_dupes=$((apt_dupes + 1))
    fi
  done
  [ "$apt_dupes" -eq 0 ] && ok "no apt package duplicates a declared one"
else
  ok "not a dpkg system, nothing to check"
fi

# ---------------------------------------------------------------------------
section "Summary"
if [ "$drift" -eq 0 ]; then
  ok "no drift that would change what you run"
  echo
  echo "  Lines marked ! above are not failures. They are software Nix does not"
  echo "  manage: fine on this machine, absent on the next one."
else
  echo "  Drift found. Nothing above has been changed; fix what matters to you."
  echo
  echo "  Rule of thumb: if a tool is in home.nix, the Nix copy should be the"
  echo "  one that runs. Otherwise flake.lock is not describing this machine."
fi
echo
exit "$drift"
