# 00 - What changed from the macOS version

This page explains every decision that differs from the video, and why. If you
have watched the video, read this first; the rest of the docs assume it.

## The one structural change: no nix-darwin

The video's setup has two layers:

```
nix-darwin      -> manages macOS itself (dock, Finder, Homebrew, users)
  home-manager  -> manages $HOME (dotfiles, packages, zsh)
```

nix-darwin is a macOS-only project. It works by writing macOS `defaults`,
managing launchd services, and driving Homebrew. None of that exists on Windows
or on a stock Ubuntu, so the outer layer simply has no counterpart here.

What is left is home-manager, which is cross-platform and can run **standalone**:

```
home-manager (standalone)  -> manages $HOME
```

Consequences that ripple through the whole repo:

1. There is no `configuration.nix`. Everything that used to be in it either
   moved into `home.nix` (packages) or moved out of Nix entirely
   (`system.defaults` became `windows/settings.ps1`).
2. `darwin-rebuild switch` becomes `home-manager switch`.
3. **No `sudo`.** nix-darwin edits system state and needs root; standalone
   home-manager only writes your home directory and must not be run as root.
4. The flake exposes `homeConfigurations."wsl"` instead of
   `darwinConfigurations."mac"`.

## The second structural change: the Windows boundary

WSL is a Linux VM. Anything that has to draw pixels, receive keystrokes from
Windows, or be seen by the Windows font renderer is a **Windows** program and
cannot be installed by Nix inside WSL.

That splits the video's setup across a boundary:

| Component | Runs where | Installed by |
| --- | --- | --- |
| Windows Terminal | Windows | ships with Windows; its settings stay yours |
| Hack Nerd Font | Windows (and Linux) | `home.nix` (Nix store), copied across by `install-windows-font.sh` |
| zsh, Starship | WSL | `home.nix` |
| Neovim, ripgrep, fd, fzf, jq, lazygit | WSL | `home.nix` |
| herdr | WSL | `modules/herdr.nix` |
| Claude Code / Codex / opencode | WSL | `home.nix` |

The config *files* all stay in WSL, in this repo, and WSL pushes what Windows
needs across the boundary itself. See [05-terminal.md](05-terminal.md).

## Line-level mapping

### `nixpkgs-26.05-darwin` becomes `nixos-26.05`

The `-darwin` branches only build macOS packages. The Linux release branch is
named `nixos-<release>` even when you are not running NixOS. `home-manager`
keeps the same `release-26.05` branch name on both platforms.

### `nixpkgs.hostPlatform = "aarch64-darwin"` becomes `system = "x86_64-linux"`

Same idea, different value. Use `aarch64-linux` only on Windows-on-ARM.

### Homebrew disappears entirely

```nix
# macOS
homebrew = {
  onActivation.cleanup = "zap";
  brews  = [ "herdr" ];
  casks  = [ "wezterm" "claude-code" ];
};
```

Homebrew exists for Linux, but using it here would be strictly worse: nixpkgs
already has everything except herdr, and a second package manager would break
the single-source-of-truth property that `cleanup = "zap"` was protecting in the
first place. So:

- `claude-code` is dropped rather than moved. It is in nixpkgs, but it updates
  itself into `~/.local/bin`, and a Nix-store copy both freezes that and shadows
  the newer one on `PATH`. Declarative packaging and self-updating binaries are
  a genuinely bad match.
- `wezterm` is dropped entirely in favour of Windows Terminal, which is already
  installed and needs no package manager. See [05-terminal.md](05-terminal.md)
  for why the terminal emulator matters less here than it looks.
- `herdr` gets packaged by hand in [`modules/herdr.nix`](03-modules-herdr-nix.md),
  pinned by version and hash. That is actually *stronger* than the Homebrew
  formula the video uses, because the hash makes the download verifiable.

The `cleanup = "zap"` guarantee (nothing installed outside the config survives a
rebuild) is preserved for the Nix half automatically: anything not listed in
`home.packages` is not in your profile after a switch.

### `system.defaults` is dropped

| macOS setting | Windows equivalent |
| --- | --- |
| `AppleInterfaceStyle = "Dark"` | `AppsUseLightTheme` / `SystemUsesLightTheme` = 0 |
| `KeyRepeat = 2` | `KeyboardSpeed = 31` (inverted scale) |
| `InitialKeyRepeat = 15` | `KeyboardDelay = 0` (inverted scale) |
| `AppleShowAllExtensions = true` | `HideFileExt = 0` |
| `dock.autohide` + `_HIHideMenuBar` | taskbar auto-hide (`StuckRects3`) |
| `finder.CreateDesktop = false` | `HideIcons = 1` |
| `trackpad.Clicking = true` | `PrecisionTouchPad\TapsEnabled = 1` |
| `finder.FXPreferredViewStyle = "Nlsv"` | no reliable equivalent, skipped |

An earlier version of this port shipped a `settings.ps1` that wrote these to
the registry. It was removed. The reasoning: these are desktop appearance
preferences, not development environment, and unlike everything else in this
repo nothing reverts them. Shipping imperative registry writes under a banner of
reproducibility was overclaiming. Set them once in the Windows Settings app.

The one that genuinely affects the terminal, dark theme, is handled by the
colour scheme instead.

### The Neovim clipboard needs a bridge

`clipboard = 'unnamedplus'` works on macOS because Neovim finds `pbcopy`.
Inside WSL there is no X selection connected to Windows, so yanks would vanish.
`vim_config.lua` therefore defines an explicit provider using `clip.exe` and
`powershell.exe`. Details in [06-neovim.md](06-neovim.md).

### zsh has to be made the login shell

macOS already uses zsh. Ubuntu uses bash, and `chsh` refuses any shell not
listed in `/etc/shells`, so `bootstrap.sh` registers the Nix zsh there first.

### systemd has to be enabled

Not a macOS/Linux difference so much as a WSL quirk. Multi-user Nix runs a
daemon, and the Determinate installer wires it up through systemd. Older WSL
images boot without an init system. `bootstrap.sh` detects this, writes
`/etc/wsl.conf`, and asks you to `wsl --shutdown` once.

### Small quality-of-life additions not in the video

These exist only because WSL has sharp edges the video never hits:

- zsh jumps back to `$HOME` if it starts in `/mnt/...`, because the 9p mount to
  the Windows filesystem is drastically slower than the Linux one.
- A `winhome` function and an `e` alias (`explorer.exe .`) for crossing the boundary.
- A WSL section in `AGENTS.md` telling agents not to use apt and not to put
  repos on `/mnt/c`.
