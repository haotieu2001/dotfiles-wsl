# 09 - Talking to Windows

Two scripts in `scripts/`, both run from inside WSL. They are the only things
here that reach outside Linux.

| Script | Runs | Writes |
| --- | --- | --- |
| `install-windows-font.sh` | every rebuild | the Windows font folder and registry |
| `apply-windows-terminal-theme.sh` | install only | Windows Terminal's `settings.json` |

An older version of this repo used PowerShell scripts you had to run yourself.
Neither of these needs that. WSL can run Windows programs and write to the
Windows disk, so both happen inside the same bootstrap.

The difference in the "Runs" column is the whole design, explained in
[05-terminal.md](05-terminal.md). In short: the font has a right answer and
nothing else manages it, so we copy it forever. `settings.json` belongs to
Windows Terminal, so this repo writes it once, on a computer with nothing to
lose.

Both are safe to run again, and safe to run by hand.

---

# `install-windows-font.sh`

Copies Hack Nerd Font out of the Nix store into the Windows font folder and
registers it, so Windows can draw it.

## Line by line

```bash
export PATH="$HOME/.nix-profile/bin:$PATH"
```

Not decoration. The font comes from what home-manager installed. When
`bootstrap.sh` runs this script, the shell it uses was started *before* the
first build, so those tools are not findable yet. Setting this here means the
script does not care how it was started.

### Checks before doing anything

```bash
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  info "not running under WSL, nothing to do"
  exit 0
fi
```

It stops with success, not failure. On a normal Linux machine there is no
Windows side, and that is fine, so `rebuild.sh` should not fail because of it.

```bash
for bin in cmd.exe reg.exe wslpath; do
  command -v "$bin" >/dev/null 2>&1 || { warn ...; exit 1; }
done
```

The bridge to Windows has to actually be there. Without this check, the lookups
below fail quietly and the script would work out a nonsense destination.

```bash
WIN_HOME_RAW="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r' || true)"
case "$WIN_HOME_RAW" in
  [A-Za-z]:\\*) : ;;
  *) warn "could not read %USERPROFILE% ..."; exit 1 ;;
esac
```

We ask Windows where your user folder is, instead of guessing
`/mnt/c/Users/<same-name-as-linux>`. The two names are often different.
`tr -d '\r'` removes the extra character Windows puts at the end of the line.

The `case` check is there because of a real trap: **`wslpath ""` returns `.` and
reports success.** Without checking that the value looks like `C:\Users\name`
first, an empty answer would quietly mean "the folder I am in", and the font
would be written wherever you happened to run the script. This was a real bug,
found by running the script with the Windows bridge removed from `PATH`.

```bash
WIN_HOME="$(wslpath -u "$WIN_HOME_RAW" 2>/dev/null || true)"
case "$WIN_HOME" in /*) : ;; *) warn ...; exit 1 ;; esac
```

A second check: the converted path must start from the top of the file system.

### The font itself

```bash
src_dir="$(dirname "$(readlink -f "$HOME/.nix-profile/share/fonts/truetype/NerdFonts/Hack/HackNerdFont-Regular.ttf" ...)")"
```

The font comes from the **Nix store**, and that is the important choice here. An
earlier version downloaded a copy from GitHub. Taking it from `nerd-fonts.hack`
in `home.packages` instead means the font version is locked by `flake.lock` like
everything else, and there is only one copy to keep in step.

```bash
for face in Regular Bold Italic BoldItalic; do
  ...
  if [ ! -f "$dest" ] || ! cmp -s "$src" "$dest"; then cp -f "$src" "$dest"; changed=1; fi
```

Only the four styles the terminal needs, out of the twelve in the package.
`cmp` compares the files and skips copying identical ones, which is what makes
the "already up to date" case fast and quiet.

```bash
  reg.exe add 'HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
    /v "$label" /t REG_SZ /d "$(wslpath -w "$dest")" /f
```

Copying the file is not enough. Windows only offers a font once it is registered.
`HKCU` means "for this user only", so you do not need admin rights, and
`wslpath -w` converts the path back to the `C:\...` form Windows expects.

A newly registered font is sometimes invisible to programs that are already
running, which is why the script suggests signing out when something changed.

---

# `apply-windows-terminal-theme.sh`

Adds `windows/blackpanther.json` and `windows/profile-defaults.json` into
Windows Terminal's `settings.json`, and copies the background picture to the
Windows side.

It repeats the checks above - WSL, the Windows bridge, and the `%USERPROFILE%`
lookup with the same `wslpath ""` trap - and adds four of its own.

### Finding settings.json

```bash
"$base/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
"$base/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json"
"$base/Microsoft/Windows Terminal/settings.json"
```

There are three versions of Windows Terminal, each keeping its settings
somewhere different. We check the normal Store one first, since that is what
Windows 11 comes with.

If none exists, the script stops with **success** and a hint. It just means you
have never opened Windows Terminal, so it has not written a settings file yet.
That is a "come back later", not a failed install.

### Checking the file is readable

```bash
if ! jq empty "$SETTINGS" >/dev/null 2>&1; then ... exit 0; fi
```

Windows Terminal accepts comments and extra commas in its settings file. The
`jq` tool does not. So a file you edited by hand can be perfectly fine for the
program and unreadable here. The script refuses to touch a file it cannot read,
rather than risk damaging it.

### Only doing this once

```bash
if [ "$FORCE" -eq 0 ] && jq -e '.schemes // [] | any(.name == "blackpanther")' ...; then
  info "theme already present; leaving your terminal settings alone"
  exit 0
fi
```

The line that makes the whole design work. Once your colours are in the file,
this script never writes again unless you pass `--force`. Running `bootstrap.sh`
again on a computer you have since customised cannot undo your changes.

### Merging

```bash
.schemes = ((.schemes // []) | map(select(.name != $scheme[0].name)) + [$scheme[0]])
| .profiles.defaults = ((.profiles.defaults // {}) * $defaults)
```

Both halves only add:

- **Colours:** remove any scheme with the same name, then add ours. So running
  with `--force` updates it in place instead of piling up copies, and every other
  scheme you have is kept.
- **Settings:** `*` merges two sets of values, so anything this repo does not
  mention stays as it was. Your profile list, keyboard shortcuts and actions are
  never touched.

The background picture path is filled in while merging. The file in git holds a
placeholder, because a real path contains a Windows username that would be wrong
on any other computer.

### Writing safely

```bash
cp -f "$SETTINGS" "$BACKUP"          # settings.json.pre-dotfiles-wsl.<date>
jq ... > "$TMP"
jq empty "$TMP" || { warn ...; exit 1; }
cp -f "$TMP" "$SETTINGS"
```

Save a copy first, build the new file somewhere else, check it can be read, and
only then replace the original. A failed merge can never leave you with a
terminal that will not start.

---

## How repeatable is this, honestly

The font really is locked: same `flake.lock`, same file, on any computer. That
part is a real promise.

The colours are a weaker promise, and it is worth being clear. A new computer
gets your exact colours, font size, see-through level and background, which is
the point and what a new laptop actually needs. But it is a **starting point**,
not a sync. Change something in the Settings screen afterwards and this repo
will neither know nor care. Windows Terminal itself is whatever version Windows
gives you.

The rule this settles on: **lock what has a right answer, set up what is taste
once, then leave it to the person looking at the screen.** Writing personal
taste over and over on every rebuild is what the older version got wrong.
