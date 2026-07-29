# 09 - The Windows bridge

One script, `scripts/install-windows-font.sh`, run from inside WSL. It is the
only thing in this repo that reaches outside the Linux filesystem.

The earlier version of this port used two PowerShell scripts run separately.
This replaces both. WSL can call Windows executables and write to the Windows
filesystem directly, so everything can be driven from the same `./rebuild.sh`
that manages the rest of the setup.

## What it does

Exactly one thing: copies Hack Nerd Font out of the Nix store into the Windows
per-user font directory and registers it, so Windows can render it.

It used to also merge a colour scheme and profile settings into Windows
Terminal's `settings.json`. That was removed - see
[05-terminal.md](05-terminal.md) for why a repo should not be writing a file the
application itself owns.

Idempotent. Run it as many times as you like.

## Line by line

```bash
export PATH="$HOME/.nix-profile/bin:$PATH"
```

Not decoration. The font comes from the home-manager profile, and when
`bootstrap.sh` calls this script the calling shell was started *before* the
first switch ever ran, so that profile is not on `PATH` yet. Setting it here
means the script does not depend on how it was invoked.

### Preconditions

```bash
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  info "not running under WSL, nothing to do"
  exit 0
fi
```

Exits 0, not 1. On a plain Linux box there is no Windows side and that is not
an error, so `rebuild.sh` should not fail because of it.

```bash
for bin in cmd.exe reg.exe wslpath; do
  command -v "$bin" >/dev/null 2>&1 || { warn ...; exit 1; }
done
```

Windows interop has to actually be present. Without this check the lookups
below fail quietly and the script computes a nonsense destination.

```bash
WIN_HOME_RAW="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r' || true)"
case "$WIN_HOME_RAW" in
  [A-Za-z]:\\*) : ;;
  *) warn "could not read %USERPROFILE% ..."; exit 1 ;;
esac
```

Windows is asked where the user profile is, rather than assuming
`/mnt/c/Users/<same-name-as-linux>`; the two usernames are frequently
different. `tr -d '\r'` strips the carriage return Windows appends.

The `case` guard is there because of a genuine trap: **`wslpath ""` returns `.`
with exit status 0.** Without validating that the value looks like `C:\Users\name`
first, an empty result would silently resolve to the current directory, and the
font would be written into whatever directory you happened to run the script
from. This was a real bug, found by running the script with interop stripped
out of `PATH`.

```bash
WIN_HOME="$(wslpath -u "$WIN_HOME_RAW" 2>/dev/null || true)"
case "$WIN_HOME" in /*) : ;; *) warn ...; exit 1 ;; esac
```

Belt and braces: the converted path must be absolute.

### The font

```bash
src_dir="$(dirname "$(readlink -f "$HOME/.nix-profile/share/fonts/truetype/NerdFonts/Hack/HackNerdFont-Regular.ttf" ...)")"
```

The font comes from the **Nix store**, which is the important design decision
here. The first version of this port downloaded a pinned release from GitHub;
sourcing it from `nerd-fonts.hack` in `home.packages` instead means the font
version is pinned by `flake.lock` along with everything else, and there is only
one copy to keep in step.

```bash
for face in Regular Bold Italic BoldItalic; do
  ...
  if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then cp -f "$src" "$dest"; changed=1; fi
```

Only the four faces the terminal actually needs, out of the twelve in the
package. `cmp` avoids rewriting identical files, which is what makes the
"already current" path fast and silent.

```bash
  reg.exe add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
    /v "$label" /t REG_SZ /d "$(wslpath -w "$dest")" /f
```

Copying a font file is not enough; Windows only enumerates it once registered.
`HKCU` is a per-user install, so no administrator rights are needed, and
`wslpath -w` converts back to the `C:\...` form the registry expects.

Newly registered fonts are sometimes invisible to already-running processes,
hence the sign-out hint when something actually changed.

## Reproducibility, honestly

The font is Nix-pinned: same `flake.lock`, same bytes, on any machine. That part
is a real guarantee.

Everything else about the Windows side is not, and the repo no longer pretends
otherwise. Windows Terminal is whatever version Windows ships, and its
`settings.json` is yours. Earlier drafts of this port tried to close that gap by
merging our own keys into that file on every rebuild, which bought a weaker kind
of reproducibility - reasserting values, never removing them, and silently
overwriting whatever the user had chosen.

The honest boundary turned out to be the more useful one: **pin what has a
correct answer, leave what is taste to the person looking at the screen.** One
small script, one clearly-stated job.
