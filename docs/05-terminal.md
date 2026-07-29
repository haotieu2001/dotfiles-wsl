# 05 - The terminal

Windows Terminal, seeded once from this repo and yours thereafter.

## Why Windows Terminal

An earlier version of this repo installed WezTerm on Windows through winget and
configured it from a Lua file read over `\\wsl.localhost`. It worked, and it was
the worst part of the setup:

- **It broke the repo's central promise.** The premise is that a clone plus
  `./bootstrap.sh` reproduces everything. The terminal, its font and its
  settings sat outside Nix entirely, so they were exactly the parts a fresh
  machine could not reproduce.
- **winget ships a stale WezTerm.** The published stable build was years old.
- **It needed a second install step** in PowerShell, on a UNC path, plus a
  loader stub whose hardcoded path broke if the distro was renamed.
- **The font had to be installed twice**, from two different sources that could
  drift apart.

Windows Terminal is already installed on every modern Windows machine, is fast
and GPU-accelerated, and has the best WSL integration available.

The key realisation is that **the terminal emulator matters far less here than
it appears to**, because herdr provides the workspace, tab, pane and session
layer (see [07-herdr.md](07-herdr.md)). What is actually needed from the host
terminal is narrow: fast, correct VT rendering, truecolor, and a Nerd Font.

## Seed once, then hand off

Two things cross the WSL/Windows boundary, and they are governed by different
rules.

```
nerd-fonts.hack (Nix store, pinned by flake.lock)
        |  scripts/install-windows-font.sh          EVERY REBUILD
        v
%LOCALAPPDATA%\Microsoft\Windows\Fonts  + HKCU registration

windows/blackpanther.json + profile-defaults.json + blackpanther.jpg
        |  scripts/apply-windows-terminal-theme.sh  BOOTSTRAP ONLY
        v
Windows Terminal settings.json  (+ %LOCALAPPDATA%\dotfiles-wsl\ for the image)
```

**The font is managed.** It has a correct answer - the glyphs must exist, at a
version matching the rest of the build - and nothing else on the machine
manages it. Re-pushing it every rebuild costs nothing and can only fix drift.

**The theme is seeded.** `settings.json` is a file Windows Terminal *itself*
rewrites every time you change anything in its Settings UI. A repo that
reasserts its own values on every `./rebuild.sh` is in a permanent fight with
the application for ownership of that file, and whichever ran last wins. A
previous version of this repo did exactly that and it was removed.

But seeding a *fresh machine* is a different operation from reasserting on
every rebuild. A new Windows install has no colour scheme of yours in it, so
writing one takes nothing away. That is why `bootstrap.sh` applies the theme at
step 8 and `rebuild.sh` never does.

After that first write, the file is yours permanently. The script checks
whether the `blackpanther` scheme is already present and exits without touching
anything if it is.

## What gets seeded

| File | Contents |
| --- | --- |
| `windows/blackpanther.json` | The colour scheme: 16 ANSI colours, background, foreground, cursor, selection |
| `windows/profile-defaults.json` | Font face and size, opacity, padding, cursor shape, scrollback, antialiasing, background image settings |
| `windows/blackpanther.jpg` | The background image, copied to `%LOCALAPPDATA%\dotfiles-wsl\` |

The image is copied to a Windows-side path rather than referenced in place.
Windows Terminal is a Windows process, so pointing it at `\\wsl.localhost` would
work but reads slowly and breaks if the distro is renamed.

The script rewrites the `backgroundImage` path for the machine it is running on,
so the committed JSON carries a `__BACKGROUND_IMAGE__` placeholder rather than
a username that would be wrong on any other laptop.

## Changing the theme

**For this machine only**, which is the common case: use Windows Terminal's
Settings UI. Nothing in this repo will overwrite it.

**For every future machine**: edit the files in `windows/`, commit, and re-seed
explicitly:

```bash
./scripts/apply-windows-terminal-theme.sh --force
```

`--force` is the only way to make this repo overwrite a terminal you have
already customised, and it exists precisely so that overwriting is a deliberate
act rather than a side effect of a rebuild.

Both writes are backed up first, to
`settings.json.pre-dotfiles-wsl.<timestamp>` next to the original.

## Safety behaviour

The script declines to act rather than risk your settings, in three cases:

- **No `settings.json` found.** Windows Terminal has not been launched yet, so
  it has not written its config. It tells you to launch it once and re-run.
- **`settings.json` is not strict JSON.** Windows Terminal accepts JSONC -
  comments and trailing commas - which `jq` cannot parse. Rather than mangle a
  hand-edited file, the script stops and tells you.
- **The merge produced invalid JSON.** Validated before replacing the original,
  so a broken merge can never leave you with a terminal that will not start.

The merge itself is additive. Schemes other than `blackpanther` are kept, your
own keys under `profiles.defaults` survive, and `profiles.list`, `actions` and
`keybindings` are never touched.

## Setting colours by hand

A scheme is an object under `schemes`, referenced by name from either
`profiles.defaults` or an individual profile:

```json
{
  "schemes": [ { "name": "my-theme", "background": "#050008", "...": "..." } ],
  "profiles": { "defaults": { "colorScheme": "my-theme", "opacity": 80 } }
}
```

Put it in `profiles.defaults` to apply it to every profile, or on one profile to
scope it. Transparency is `opacity` (0-100); add `"useAcrylic": true` for a
blurred backdrop instead of plain see-through.

For transparency to be visible behind the editor, Neovim must not paint an
opaque background - see the `transparency` flag in [06-neovim.md](06-neovim.md).

Two settings worth knowing about:

- `"antialiasingMode": "grayscale"` renders noticeably better than the default
  ClearType subpixel rendering on a dark background. It is in the seeded
  defaults for that reason.
- There is no `startingDirectory` on purpose: its interpretation differs
  between WSL and Windows profiles. The zsh guard in `home.nix` solves the real
  problem instead, bouncing to `$HOME` if the shell starts under `/mnt`.

## Using a different terminal

Nothing else in this repo depends on Windows Terminal. If you prefer Alacritty,
Ghostty, or WezTerm from its nightly channel, install it yourself; the WSL side
is unaffected, and the font script still works since it only installs a font.
You need exactly two things from any host terminal: Hack Nerd Font and truecolor
support.

For a fully Nix-managed terminal with no Windows-side step at all, add
`wezterm` or `kitty` to `home.packages` and run it as a Linux GUI app through
WSLg. That is genuinely 100% reproducible. The tradeoff is the WSLg compositing
layer: extra input latency, blurrier text on high-DPI displays, and
inconsistent GPU acceleration. Worth it if reproducibility is the priority.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Boxes instead of icons | Font registered but not yet picked up. Sign out of Windows and back in. |
| Font not offered in Settings | The install script has not run, or ran before `nerd-fonts.hack` was in `home.packages`. Run `./scripts/install-windows-font.sh`. |
| Theme not applied after bootstrap | Windows Terminal had never been launched, so there was no `settings.json` to merge into. Launch it, then run `./scripts/apply-windows-terminal-theme.sh`. |
| `settings.json is not strict JSON` | Comments or trailing commas in the file. Remove them, or apply `windows/blackpanther.json` by hand. |
| Background image missing | The image is copied to `%LOCALAPPDATA%\dotfiles-wsl\`. Re-run the theme script with `--force`. |
| Background opaque | `opacity` must be below 100; also check Neovim's `transparency`. |
| Opens in `/mnt/c/...` | The zsh guard in `home.nix` handles this; make sure you are on zsh. |
| Colours changed unexpectedly | Not a rebuild - `rebuild.sh` never writes `settings.json`. Check Windows Terminal's own Settings UI, or whether someone ran the theme script with `--force`. |
