# 05 - The terminal

The video's 15:33 chapter installs WezTerm as a Homebrew cask and configures it
in Lua. This port takes a different route, and the reasoning matters more than
the config.

## Why not WezTerm here

The first version of this repo did port WezTerm faithfully: installed on
Windows through winget, configured by a Lua file in the repo that the Windows
side read over `\\wsl.localhost`. It worked, but it was the worst part of the
port:

- **It broke the video's central promise.** The whole premise is that
  `rebuild.sh` reproduces everything. The terminal, its font, and its settings
  sat outside Nix entirely, so they were exactly the parts a fresh machine
  could not reproduce.
- **winget ships a stale WezTerm.** The published stable build is from
  February 2024, over two years old.
- **It needed a second install step** in PowerShell, on a UNC path, plus a
  loader stub whose hardcoded path broke if the distro was renamed.
- **The font had to be installed twice**, from two different sources that could
  drift apart.

## What replaces it

Windows Terminal, which is already installed on every modern Windows machine,
is fast, GPU-accelerated, and has the best WSL integration available.

The key realisation is that **the terminal emulator matters far less in this
setup than it appears to**, because herdr provides the workspace, tab, pane and
session layer (see [07-herdr.md](07-herdr.md)). WezTerm's own multiplexing and
its large config surface are redundant here. What is actually needed from the
host terminal is narrow: fast, correct VT rendering, truecolor, and a Nerd
Font. Windows Terminal does all of that.

So the terminal is reduced to two data files in this repo, pushed across the
boundary by one script, driven from inside WSL:

```
home/windows-terminal/rose-pine-moon.json   the colour scheme
home/windows-terminal/profile.json          font, opacity, padding, cursor
        |
        |  scripts/sync-windows-terminal.sh   (runs inside WSL)
        v
Windows Terminal settings.json               merged, never overwritten
```

No PowerShell step, no admin rights, no UNC stub, and `./rebuild.sh` still does
everything in one command.

## `home/windows-terminal/rose-pine-moon.json`

A standard Windows Terminal colour scheme. `name` is the identifier the profile
refers to; changing it means changing `colorScheme` in `profile.json` too.

```json
{
  "name": "Rose Pine Moon",
  "background": "#232136",
  "foreground": "#E0DEF4",
  "cursorColor": "#56526E",
  "selectionBackground": "#44415A",
```

`#232136` is rose-pine moon's `base` and `#E0DEF4` its `text`. The cursor uses
`highlightHigh` and the selection `highlightMed`, so both read clearly against
the background without competing with the syntax colours.

```json
  "black": "#393552",
  "red": "#EB6F92",
  "green": "#3E8FB0",
  "yellow": "#F6C177",
  "blue": "#9CCFD8",
  "purple": "#C4A7E7",
  "cyan": "#EA9A97",
  "white": "#E0DEF4",
```

The sixteen ANSI slots, using rose-pine's canonical mapping: `love` is red,
`pine` is green, `gold` is yellow, `foam` is blue, `iris` is purple and `rose`
is cyan. The names are a historical accident of the ANSI palette; what matters
is that this is the mapping the rose-pine Neovim theme expects, so the editor
and everything else in the terminal agree.

The bright variants repeat the same values, which is deliberate. rose-pine is a
low-contrast palette, and inventing brighter variants would break its balance.

## `home/windows-terminal/profile.json`

Merged onto the WSL profile only. Every key not listed here is left as
Windows Terminal had it.

```json
  "colorScheme": "Rose Pine Moon",
  "font": { "face": "Hack Nerd Font", "size": 11 },
```

`face` must match the name the font registered under on Windows. The sync
script registers exactly `Hack Nerd Font`.

Size 11 is the Windows equivalent of the video's macOS `15.0`, which is a
Retina value. Adjust freely.

```json
  "opacity": 90,
  "useAcrylic": true,
```

The translucent frosted background from 17:12. On Windows Terminal, `opacity`
is 0-100 and `useAcrylic` selects the blurred backdrop rather than plain
transparency. This replaces the video's `window_background_opacity` plus
`macos_window_background_blur`.

For the blur to be visible behind the editor, Neovim must not paint an opaque
background - see the `transparency` flag in [06-neovim.md](06-neovim.md).

```json
  "padding": "12",
  "antialiasingMode": "grayscale",
  "cursorShape": "filledBox",
  "scrollbarState": "hidden",
```

`grayscale` antialiasing renders noticeably better than the default ClearType
subpixel rendering on a dark background. `scrollbarState: hidden` gets close to
the frameless look from 17:20; Windows Terminal has no equivalent of removing
the title bar per-profile, so that is one cosmetic detail the port does not
reproduce.

```json
  "snapOnInput": true,
  "historySize": 20000
```

`snapOnInput` jumps back to the prompt when you type after scrolling. The large
scrollback matters when reading agent output.

Note there is no `startingDirectory`. Setting it is tempting but fragile: its
interpretation differs between WSL and Windows profiles. The zsh guard in
`home.nix` handles the real problem instead, bouncing to `$HOME` if the shell
starts anywhere under `/mnt`.

## Using a different terminal

Nothing else in this repo depends on Windows Terminal. If you prefer Alacritty,
Ghostty, or WezTerm from its nightly channel, install it yourself and skip the
sync script; the WSL side is unaffected. You need exactly two things from any
host terminal: Hack Nerd Font (still installed by the sync script) and
truecolor support.

For a fully Nix-managed terminal with no Windows-side step at all, add
`wezterm` or `kitty` to `home.packages` and run it as a Linux GUI app through
WSLg. That is genuinely 100% reproducible. The tradeoff is the WSLg compositing
layer: extra input latency, blurrier text on high-DPI displays, and
inconsistent GPU acceleration. Worth it if reproducibility is the priority.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| Boxes instead of icons | Font registered but not yet picked up. Sign out of Windows and back in. |
| Colours unchanged | The profile name did not match. See [09-windows-bridge.md](09-windows-bridge.md). |
| Background opaque | `useAcrylic` needs `opacity` below 100; also check Neovim's `transparency`. |
| Opens in `/mnt/c/...` | The zsh guard in `home.nix` handles this; make sure you are on zsh. |
| Want your old settings back | `settings.json.dotfiles-backup`, next to the file the script edits. |
