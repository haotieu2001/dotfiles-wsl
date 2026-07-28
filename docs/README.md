# Docs

Line-by-line explanation of every file in this repo.

Read [00](00-what-changed-from-macos.md) first if you have seen the video: it
covers the two structural changes (no nix-darwin, and the Windows/WSL boundary)
that everything else follows from.

| Doc | Covers |
| --- | --- |
| [00 - What changed from macOS](00-what-changed-from-macos.md) | Every deviation from the video and the reasoning |
| [01 - flake.nix](01-flake-nix.md) | Inputs, pinning, the `user` line, `homeConfigurations` |
| [02 - home.nix](02-home-nix.md) | Packages, zsh, Starship, and `mkOutOfStoreSymlink` |
| [03 - modules/herdr.nix](03-modules-herdr-nix.md) | Packaging a pinned upstream binary in Nix |
| [04 - bootstrap.sh and rebuild.sh](04-bootstrap-and-rebuild.md) | Both scripts, step by step |
| [05 - WezTerm](05-wezterm.md) | The config, and how Windows reads it out of WSL |
| [06 - Neovim](06-neovim.md) | Every Lua file, including the WSL clipboard bridge |
| [07 - herdr](07-herdr.md) | Keybindings and running agents in panes |
| [08 - Agents](08-agents.md) | `AGENTS.md` fan-out and the Claude status line |
| [09 - Windows scripts](09-windows-scripts.md) | `setup-windows.ps1` and `settings.ps1` |
| [10 - Troubleshooting](10-troubleshooting.md) | WSL-specific failure modes |

## Reading order

**Setting up:** the root [README](../README.md), then
[04](04-bootstrap-and-rebuild.md), then [09](09-windows-scripts.md).

**Understanding it:** [00](00-what-changed-from-macos.md),
[01](01-flake-nix.md), [02](02-home-nix.md).

**Customizing:** [02](02-home-nix.md) for packages and shell,
[05](05-wezterm.md) for the terminal, [06](06-neovim.md) for the editor,
[08](08-agents.md) for agent behavior.
