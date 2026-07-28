# 09 - The Windows bridge

One script, `scripts/sync-windows-terminal.sh`, run from inside WSL. It is the
only thing in this repo that reaches outside the Linux filesystem.

The earlier version of this port used two PowerShell scripts run separately.
This replaces both. WSL can call Windows executables and write to the Windows
filesystem directly, so everything can be driven from the same `./rebuild.sh`
that manages the rest of the setup.

## What it does

1. Copies Hack Nerd Font out of the Nix store into the Windows per-user font
   directory and registers it, so Windows can render it.
2. Merges the colour scheme and profile settings from `home/windows-terminal/`
   into Windows Terminal's `settings.json`.

Both are idempotent. Run it as many times as you like.

## Line by line

```bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
FRAGMENTS="$DIR/home/windows-terminal"
export PATH="$HOME/.nix-profile/bin:$PATH"
```

The `PATH` line is not decoration. `jq` and the font both come from the
home-manager profile, and when `bootstrap.sh` calls this script the calling
shell was started *before* the first switch ever ran, so that profile is not on
`PATH` yet. Setting it here means the script does not depend on how it was
invoked.

### Preconditions

```bash
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  info "not running under WSL, nothing to sync"
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

### The settings merge

```bash
settings="$(ls -1 "$WIN_HOME"/AppData/Local/Packages/Microsoft.WindowsTerminal*/LocalState/settings.json ...)"
```

The glob covers both the stable and Preview package identities.

```bash
if ! jq -e . "$settings" >/dev/null 2>&1; then
  warn "settings.json is not valid JSON (comments?); leaving it alone"
  return 0
fi
```

Windows Terminal's default template can contain `//` comments, which `jq`
cannot parse. Stripping them with a regex is not safe either, because the file
legitimately contains `https://` in its `$schema` key and a naive strip would
corrupt it. So the script refuses rather than risking your config. In practice
Windows Terminal writes plain JSON once it has saved settings itself.

```bash
jq --slurpfile scheme ... --slurpfile prof ... --arg distro "$DISTRO" '
  .schemes = ((.schemes // []) | map(select(.name != $scheme[0].name)) + $scheme)
```

Replace our scheme by name and append it; every other scheme you have is
untouched. This is why an unrelated custom scheme survives a sync.

```bash
  | .profiles.list = ((.profiles.list // []) | map(
      if .name == $distro then . * $prof[0] else . end))
```

Only the profile whose name matches this distro is touched. The `*` operator is
a recursive merge, so keys we do not mention (the GUID, the source, anything
you set by hand) are preserved. Other profiles are left completely alone.

```bash
  | .defaultProfile = (([$l[] | select(.name == $distro) | .guid] | first) // .defaultProfile)
```

Makes the WSL profile the default, falling back to the existing value if no
matching profile exists yet.

```bash
  if [ -n "$(jq -e --slurpfile a ... --slurpfile b ... -n 'if $a[0] == $b[0] then empty else 1 end')" ]; then
    cp -f "$settings" "$settings.dotfiles-backup"
    cat "$merged" > "$settings"
```

Compares the whole document before and after and writes only on a real change,
which is what keeps repeat runs quiet and avoids churning the file's timestamp
while Windows Terminal is watching it.

Note `cat "$merged" > "$settings"` rather than `mv`. Windows Terminal watches
that specific file, and replacing the file node (as `mv` does) can break the
watch or trip permissions on the Windows filesystem. Writing through the
existing node avoids both.

A backup is written next to the original as `settings.json.dotfiles-backup`
before any change.

### The final check

```bash
if ! jq -e --arg d "$DISTRO" '[.profiles.list[]? | select(.name == $d)] | length > 0' ...
  warn "no Windows Terminal profile named '$DISTRO' yet."
```

Windows Terminal generates the WSL profile the first time it runs. On a machine
where it has never been opened, there is nothing to patch yet, so the script
says exactly that instead of appearing to succeed.

## Reproducibility, honestly

The font is Nix-pinned, and the terminal settings are generated from files
committed in this repo and re-applied on every `./rebuild.sh`. That is a real
improvement over the first version of this port, where the terminal was
installed by winget and configured outside the repo entirely.

It is still not the same guarantee as the Nix half. Windows Terminal itself is
whatever version Windows ships, `settings.json` is a merge into a file the OS
also writes, and nothing reverts a change you make by hand in the Settings UI.
Re-running reasserts our keys; it does not remove anything else. That is the
honest boundary, and it is why this lives in one clearly-marked script rather
than being described as part of the declarative build.
