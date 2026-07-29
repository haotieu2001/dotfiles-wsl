# 05 - The terminal

Windows Terminal, set up once from this repo, and yours after that.

## Why Windows Terminal

An older version of this repo installed WezTerm on Windows and set it up from a
Lua file read across the WSL boundary. It worked, and it was the worst part of
the setup:

- **It broke the main promise.** The whole idea is that cloning the repo and
  running `./bootstrap.sh` gives you everything back. But the terminal, its font
  and its settings sat outside Nix, so they were exactly the parts a new computer
  could not rebuild.
- **The Windows package was years out of date.**
- **It needed a second step in PowerShell**, plus a small loader file whose path
  broke if you renamed your Linux distro.
- **The font had to be installed twice**, from two different places that could
  drift apart.

Windows Terminal is already on every modern Windows machine, is fast, and works
best with WSL.

The key point is that **the terminal matters much less here than it looks**,
because herdr already gives you tabs, split windows and sessions
(see [07-herdr.md](07-herdr.md)). All we need from the terminal is that it draws
text quickly and correctly, supports lots of colours, and can use a Nerd Font.

## Set once, then hand over

Two things cross from Linux to Windows, and they follow different rules.

```
Hack Nerd Font (from the Nix store, locked by flake.lock)
        |  scripts/install-windows-font.sh          EVERY REBUILD
        v
%LOCALAPPDATA%\Microsoft\Windows\Fonts

windows/blackpanther.json + profile-defaults.json + blackpanther.jpg
        |  scripts/apply-windows-terminal-theme.sh  INSTALL ONLY
        v
Windows Terminal settings.json  (+ %LOCALAPPDATA%\dotfiles-wsl\ for the picture)
```

**The font is managed.** There is a right answer: the font must exist, at the
version everything else was built with. Nothing else on the computer looks after
it. Copying it again on every rebuild costs nothing and can only fix problems.

**The colours are set once.** Windows Terminal writes its *own*
`settings.json` every time you change something in its Settings screen. If this
repo wrote that file on every rebuild, the two would fight over it, and whoever
ran last would win. An older version of this repo did exactly that, and we
removed it.

But setting up a **new computer** is a different thing. A fresh Windows install
has no colours of yours in it, so writing some takes nothing away. That is why
`bootstrap.sh` does this at step 8 and `rebuild.sh` never does.

After that first write, the file is yours for good. The script checks whether
the `blackpanther` colours are already there and stops without touching anything
if they are.

## What gets copied

| File | What is in it |
| --- | --- |
| `windows/blackpanther.json` | The colours: 16 text colours, background, foreground, cursor, selection |
| `windows/profile-defaults.json` | Font name and size, see-through level, padding, cursor shape, scrollback, text smoothing, background picture settings |
| `windows/blackpanther.jpg` | The background picture, copied to `%LOCALAPPDATA%\dotfiles-wsl\` |

The picture is copied to a Windows folder instead of being read where it is.
Windows Terminal is a Windows program, so it *can* read files across the WSL
boundary, but it is slow and breaks if you rename your distro.

The script writes the correct picture path for whichever computer it runs on.
The file in git holds a placeholder, `__BACKGROUND_IMAGE__`, because a real path
contains a Windows username that would be wrong on any other machine.

## Changing the colours

**For this computer only**, which is the usual case: use Windows Terminal's
Settings screen. Nothing here will overwrite it.

**For every future computer:** edit the files in `windows/`, commit them, and
then say so on purpose:

```bash
./scripts/apply-windows-terminal-theme.sh --force
```

`--force` is the only way to make this repo overwrite a terminal you have
already changed. It exists so that overwriting is always a choice, never a
side effect of a rebuild.

Either way, the old file is saved first, as
`settings.json.pre-dotfiles-wsl.<date and time>` next to the original.

## When the script refuses to act

It stops instead of risking your settings in three cases:

- **No `settings.json` found.** You have never opened Windows Terminal, so it
  has not written its settings yet. Open it once and run the script again.
- **`settings.json` is not plain JSON.** Windows Terminal also accepts comments
  and extra commas, which the `jq` tool cannot read. Rather than damage a file
  you edited by hand, the script stops and tells you.
- **The result would be broken.** The new file is checked before it replaces the
  old one, so a bad merge can never leave you with a terminal that will not
  start.

The merge only adds. Other colour schemes stay, your own settings stay, and your
list of profiles, keyboard shortcuts and actions are never touched.

## Setting colours by hand

A colour scheme is an entry under `schemes`, named, and then used by name from
either `profiles.defaults` or one single profile:

```json
{
  "schemes": [ { "name": "my-theme", "background": "#050008", "...": "..." } ],
  "profiles": { "defaults": { "colorScheme": "my-theme", "opacity": 80 } }
}
```

Put it in `profiles.defaults` to use it everywhere, or on one profile to use it
in one place. See-through level is `opacity`, from 0 to 100. Add
`"useAcrylic": true` for a blurred background instead of a plain see-through one.

For the see-through effect to show behind your editor, Neovim must not paint its
own background. See the `transparency` setting in [06-neovim.md](06-neovim.md).

Two settings worth knowing:

- `"antialiasingMode": "grayscale"` makes text look noticeably better on a dark
  background than the default. It is in the settings we copy, for that reason.
- There is no `startingDirectory` on purpose. It means different things for WSL
  and Windows profiles. The zsh rule in `home.nix` solves the real problem
  instead, by jumping back to your home folder if the shell starts under `/mnt`.

## Using a different terminal

Nothing else here needs Windows Terminal. If you prefer Alacritty, Ghostty, or a
newer WezTerm, install it yourself. The Linux side does not care, and the font
script still works because it only installs a font. You need exactly two things
from any terminal: Hack Nerd Font, and support for lots of colours.

For a terminal fully managed by Nix, with no Windows step at all, add `wezterm`
or `kitty` to `home.packages` and run it as a Linux window through WSLg. That is
completely repeatable. The cost is that WSLg adds a delay when you type, text
looks blurrier on high-resolution screens, and graphics support varies. Worth it
if being repeatable matters most to you.

## When things look wrong

| What you see | What to do |
| --- | --- |
| Boxes instead of icons | The font is installed but Windows has not noticed. Sign out of Windows and back in. |
| Font not listed in Settings | The install script has not run, or ran before `nerd-fonts.hack` was in `home.packages`. Run `./scripts/install-windows-font.sh`. |
| Colours not applied after install | Windows Terminal had never been opened, so there was no file to write into. Open it, then run `./scripts/apply-windows-terminal-theme.sh`. |
| `settings.json is not strict JSON` | Your file has comments or extra commas. Remove them, or add the colours by hand. |
| Background picture missing | The picture is copied to `%LOCALAPPDATA%\dotfiles-wsl\`. Run the script again with `--force`. |
| Background is solid | `opacity` must be below 100. Also check Neovim's `transparency`. |
| Terminal opens in `/mnt/c/...` | The zsh rule in `home.nix` handles this. Make sure you are actually using zsh. |
| Colours changed and you did not do it | Not a rebuild. `rebuild.sh` never writes that file. Check Windows Terminal's own Settings, or whether someone ran the script with `--force`. |
