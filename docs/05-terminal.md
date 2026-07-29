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

## What this repo does and does not touch

Only one thing crosses the boundary:

```
nerd-fonts.hack  (Nix store, pinned by flake.lock)
        |
        |  scripts/install-windows-font.sh   (runs inside WSL)
        v
%LOCALAPPDATA%\Microsoft\Windows\Fonts  + HKCU registration
```

**Colours, opacity, padding, background image and font size are deliberately
left alone.** An earlier version of this port did merge a scheme and profile
settings into `settings.json` on every rebuild. That was a mistake, and it is
worth being precise about why, because the reasoning generalises:

- `settings.json` is a file **Windows Terminal itself writes**, every time you
  change anything in its Settings UI. A repo that reasserts its own values on
  every `./rebuild.sh` is in a fight with the application for ownership of the
  file, and the user loses whichever one ran last.
- Every value in it is **taste**, not correctness. A colour scheme is not a
  dependency to be pinned; it is a preference that the person looking at the
  screen is the authority on.
- Adopting this repo should not silently replace a theme you already had.

This is the same rule that keeps `~/.claude` out of `home.nix`
(see [08-agents.md](08-agents.md)): **only manage what this repo owns
outright, and where nothing else writes.** The font is exactly that - it has a
correct answer (the glyphs must exist, at a version matching the rest of the
build), and nothing else on the machine manages it.

## Setting your own colours

Windows Terminal Settings UI, or edit `settings.json` directly. A scheme is an
object under `schemes`, referenced by name from either `profiles.defaults` or an
individual profile:

```json
{
  "schemes": [ { "name": "my-theme", "background": "#050008", "...": "..." } ],
  "profiles": { "defaults": { "colorScheme": "my-theme", "opacity": 80 } }
}
```

Put it in `profiles.defaults` to apply it to every profile, or on one profile to
scope it. Transparency is `opacity` (0-100); add `"useAcrylic": true` for a
blurred backdrop instead of plain see-through. That pair is the Windows Terminal
equivalent of the video's `window_background_opacity` and
`macos_window_background_blur` at 17:12.

For the transparency to be visible behind the editor, Neovim must not paint an
opaque background - see the `transparency` flag in [06-neovim.md](06-neovim.md).

Two settings worth knowing about:

- `"antialiasingMode": "grayscale"` renders noticeably better than the default
  ClearType subpixel rendering on a dark background.
- There is no `startingDirectory` here on purpose: its interpretation differs
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
| Background opaque | `opacity` must be below 100; also check Neovim's `transparency`. |
| Opens in `/mnt/c/...` | The zsh guard in `home.nix` handles this; make sure you are on zsh. |
| Colours changed unexpectedly | Not this repo - nothing here writes `settings.json`. Check Windows Terminal's own Settings UI. |
