# 10 - Troubleshooting

Failure modes specific to running this setup on WSL rather than macOS.

## Install

### `bootstrap.sh` exits telling me to run `wsl --shutdown`

Working as intended. `/etc/wsl.conf` is read only at distro start, so enabling
systemd needs a restart. From **PowerShell**, not inside WSL:

```powershell
wsl --shutdown
```

Reopen Ubuntu and re-run `./bootstrap.sh`. Confirm with:

```bash
systemctl is-system-running     # "running" or "degraded" are both fine
```

### `nix: command not found` right after installing Nix

The installer adds Nix to *new* shells. Either open a new shell, or:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### `error: experimental Nix feature 'nix-command' is disabled`

Nix came from somewhere other than the Determinate installer. Either reinstall
with it, or:

```bash
mkdir -p ~/.config/nix
echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

### `Existing file '/home/you/.bashrc' would be clobbered`

home-manager refuses to overwrite files it does not manage. Both scripts already
pass `-b backup` to rename them instead. If you hit this, you ran home-manager
by hand without that flag - use `./rebuild.sh`.

### The first build is extremely slow

Expected once. If it is slow *every* time, check the repo is not on `/mnt/c`:

```bash
pwd -P      # should start with /home, not /mnt
```

### `error: attribute 'wsl' missing`

The flake fragment does not match. `flake.nix` must define
`homeConfigurations."wsl"` and the scripts must use `#wsl`.

### `error: Package 'claude-code' has an unfree license`

`config.allowUnfree = true` is missing from the `import nixpkgs` block in
`flake.nix`, or nixpkgs was pulled in via `legacyPackages`, which ignores config.

## Shell

### Still in bash after bootstrap

Check what step 6 did:

```bash
getent passwd "$USER" | cut -d: -f7
```

If it is not the Nix zsh, run it manually:

```bash
echo "$HOME/.nix-profile/bin/zsh" | sudo tee -a /etc/shells
chsh -s "$HOME/.nix-profile/bin/zsh"
```

`chsh` fails under some WSL PAM setups. Fallback - append to `~/.bashrc`:

```bash
exec "$HOME/.nix-profile/bin/zsh" -l
```

Log out and back in either way; `chsh` does not affect the current session.

### Aliases or `$EDITOR` did not update

`sessionVariables` are exported at session start. Open a new shell.

### Prompt shows boxes or missing glyphs

Starship's symbols need a Nerd Font **on Windows**. Re-run `setup-windows.ps1`,
then sign out and back in. The Nix-installed font only serves Linux GUI apps.

## WezTerm

### Opens PowerShell instead of WSL

`WSL_DISTRO` in `home/.config/wezterm/wezterm.lua` must match `wsl -l -q`
exactly, including any suffix like `Ubuntu-26.04`.

### Config changes have no effect

Check the stub actually points at your repo:

```powershell
Get-Content $env:USERPROFILE\.wezterm.lua
```

The path must exist from Windows. Test it in Explorer. If the distro was renamed
or the repo moved, re-run `setup-windows.ps1`.

### Starts in `/mnt/c/Users/...`

`default_cwd = "~"` is missing from the `wsl_domains` entry. The zsh `case`
block in `home.nix` catches this too.

### Background is opaque

`win32_system_backdrop` needs `window_background_opacity < 1.0`. If the terminal
is translucent but Neovim is not, the colorscheme `transparency` flag is false -
see [06-neovim.md](06-neovim.md).

### Font not found after installing

Windows does not always expose a newly registered font to running processes.
Sign out and back in. Verify it registered:

```powershell
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' |
  Select-Object -Property '*Hack*'
```

## Neovim

### Yank does not reach Windows apps

Check the provider:

```
:checkhealth provider
```

It should report `WslClipboard`. If not, `vim.fn.has('wsl')` returned 0 - confirm
with `:echo has('wsl')`.

Test the underlying binaries directly:

```bash
echo hello | clip.exe        # then paste anywhere in Windows
```

### Pasted lines end with `^M`

The CR strip in the paste command is missing or mangled. The `` `r `` sequence
uses a PowerShell backtick escape and is easy to break when editing.

### Paste is noticeably slow

Each paste launches `powershell.exe` (~100ms). That is the cost of
`cache_enabled = 0`, which is what keeps Neovim from serving stale clipboard
content. Installing `win32yank` is the usual alternative if it bothers you.

### `gd` does nothing

No LSP server is configured. This matches the video, which leaves LSP out.

### Plugins did not install

lazy.nvim clones on first launch and needs network plus git. Run `:Lazy` to see
the state, `:Lazy sync` to force.

## herdr

### `herdr: command not found`

Not in the profile yet - run `./rebuild.sh`. Then confirm it came from Nix, not
from an upstream install script:

```bash
which herdr        # expect /nix/store/... or ~/.nix-profile/bin/herdr
```

### `hash mismatch in fixed-output derivation`

You bumped `version` in `modules/herdr.nix` without updating the hashes. The
error prints both expected and actual; see
[03-modules-herdr-nix.md](03-modules-herdr-nix.md).

### Escape behaves oddly in Neovim inside herdr

Usually mouse reporting. `vim_config.lua` sets `o.mouse = ''` for exactly this
reason; if you enabled the mouse, that is the cause.

### Sessions vanish after closing the terminal

They should not - the server is a Linux process independent of WezTerm. But
`wsl --shutdown`, or Windows fast startup, stops the whole VM and everything in
it. Check for leftover state with `herdr status server`.

## Agents

### Claude Code cannot update itself

Intended. It lives in the read-only Nix store, and `DISABLE_AUTOUPDATER = "1"`
turns off the attempt. Upgrade with `nix flake update` then `./rebuild.sh`.

### Status line is blank

It shells out to `jq`. Confirm `which jq` resolves; if not, `jq` is missing from
`home.packages`.

### An agent ignores `AGENTS.md`

Check the symlink resolves:

```bash
ls -l ~/.claude/CLAUDE.md
readlink -f ~/.claude/CLAUDE.md
```

A dangling link means `~/.dotfiles` does not point at the repo. Run
`./rebuild.sh`, which recreates it.

## General

### Everything is dangling after moving the repo

Every symlink resolves through `~/.dotfiles`. Re-point it:

```bash
cd /new/path/to/dotfiles-wsl && ./rebuild.sh
```

### Roll back a bad rebuild

```bash
home-manager generations              # list, newest first
/nix/store/<hash>-home-manager-generation/activate
```

### Start completely over

```bash
nix run home-manager/release-26.05 -- uninstall
/nix/nix-installer uninstall
```
