# 09 - The Windows bridge

Two scripts in `scripts/`, both run from inside WSL. They are the only things in
this repo that reach outside the Linux filesystem.

| Script | Runs | Writes |
| --- | --- | --- |
| `install-windows-font.sh` | every rebuild | the Windows per-user font store + `HKCU` |
| `apply-windows-terminal-theme.sh` | bootstrap only | Windows Terminal's `settings.json` |

An earlier version of this port used PowerShell scripts run separately. Neither
of these needs one: WSL can call Windows executables and write to the Windows
filesystem directly, so both are driven from inside the same bootstrap.

The split in the "Runs" column is the whole design and is argued in
[05-terminal.md](05-terminal.md). Short version: the font has a correct answer
and nothing else manages it, so it is re-pushed forever. `settings.json` is
owned by Windows Terminal, so this repo writes it exactly once, on a machine
that has nothing to lose.

Both are idempotent and safe to run by hand.

---

# `install-windows-font.sh`

Copies Hack Nerd Font out of the Nix store into the Windows per-user font
directory and registers it, so Windows can render it.

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

---

# `apply-windows-terminal-theme.sh`

Merges `windows/blackpanther.json` and `windows/profile-defaults.json` into
Windows Terminal's `settings.json`, and copies the background image to a
Windows-side path.

It shares the preconditions above - WSL check, interop check, `%USERPROFILE%`
lookup with the same `wslpath ""` guard - and adds four of its own.

### Finding settings.json

```bash
"$base/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
"$base/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
"$base/Microsoft/Windows Terminal/settings.json"
```

Three flavours - Store stable, Store preview, unpackaged - each with its own
location. Stable first, since that is what Windows 11 preinstalls.

If none exists, the script exits **0** with a hint. Windows Terminal has simply
never been launched, so it has not written a config yet. That is a "come back
later", not a bootstrap failure.

### The JSONC guard

```bash
if ! jq empty "$SETTINGS" >/dev/null 2>&1; then ... exit 0; fi
```

Windows Terminal reads JSONC: comments and trailing commas are legal for it and
illegal for `jq`. A hand-edited file can therefore be perfectly valid to the
application and unparseable here. The script refuses to touch a file it cannot
parse rather than risk mangling it.

### The seed-once guard

```bash
if [ "$FORCE" -eq 0 ] && jq -e '.schemes // [] | any(.name == "blackpanther")' ...; then
  info "theme already present; leaving your terminal settings alone"
  exit 0
fi
```

The line that makes the whole design work. Once the scheme is in the file, this
script never writes again unless you pass `--force`. Re-running `bootstrap.sh`
on a machine you have since customised cannot revert your colours.

### The merge

```bash
.schemes = ((.schemes // []) | map(select(.name != $scheme[0].name)) + [$scheme[0]])
| .profiles.defaults = ((.profiles.defaults // {}) * $defaults)
```

Both halves are deliberately additive:

- **Schemes**: drop any same-named scheme, then append. A `--force` re-run
  updates in place instead of accumulating duplicates, and every other scheme
  you have is preserved.
- **Defaults**: `*` is jq's recursive merge, so keys this repo does not mention
  survive. `profiles.list`, `actions` and `keybindings` are never touched at all.

The background image path is substituted at merge time. The committed JSON holds
a `__BACKGROUND_IMAGE__` placeholder, because a real path contains a Windows
username that would be wrong on any other machine.

### Write safety

```bash
cp -f "$SETTINGS" "$BACKUP"          # settings.json.pre-dotfiles-wsl.<timestamp>
jq ... > "$TMP"
jq empty "$TMP" || { warn ...; exit 1; }
cp -f "$TMP" "$SETTINGS"
```

Backup first, build the new file in a temporary location, validate it parses,
and only then replace the original. A failed merge cannot leave you with a
terminal that will not start.

---

## Reproducibility, honestly

The font is Nix-pinned: same `flake.lock`, same bytes, on any machine. That part
is a real guarantee.

The theme is a weaker claim, and worth stating precisely. A fresh machine gets
your exact colours, font size, opacity and background - which is the point, and
what a new laptop actually needs. But it is a **seed**, not a sync: change
something in the Settings UI afterwards and this repo will not know or care.
Windows Terminal itself is whatever version Windows ships.

The boundary this settles on: **pin what has a correct answer, seed what is
taste, then leave it to the person looking at the screen.** Reasserting taste on
every rebuild is what the earlier version got wrong.
