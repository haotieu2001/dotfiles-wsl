# Docs

What every file in this repo does, line by line.

Start with [00 - How it is built](00-architecture.md). It explains the four
decisions behind everything else.

| Doc | What it covers |
| --- | --- |
| [00 - How it is built](00-architecture.md) | The four decisions behind the repo |
| [01 - flake.nix](01-flake-nix.md) | Versions, locking, the `user` line, templates |
| [02 - home.nix](02-home-nix.md) | Packages, zsh, Starship, direnv, and file links |
| [03 - modules/herdr.nix](03-modules-herdr-nix.md) | How to package a downloaded program |
| [04 - The two scripts](04-bootstrap-and-rebuild.md) | `bootstrap.sh` and `rebuild.sh`, step by step |
| [05 - The terminal](05-terminal.md) | Setting colours once, and why only once |
| [06 - Neovim](06-neovim.md) | Every Lua file, and the copy-paste fix |
| [07 - herdr](07-herdr.md) | Keys, and running AI tools side by side |
| [08 - AI tools](08-agents.md) | `AGENTS.md`, and what this repo will not touch |
| [09 - Talking to Windows](09-windows-bridge.md) | The two scripts that cross over |
| [10 - When things break](10-troubleshooting.md) | Problems you may hit on WSL |
| [11 - Tools per project](11-devshells.md) | flakes and direnv |

## What to read first

**If you are installing:** the main [README](../README.md), then
[04](04-bootstrap-and-rebuild.md), then [09](09-windows-bridge.md).

**If you want to understand it:** [00](00-architecture.md),
[01](01-flake-nix.md), [02](02-home-nix.md).

**If you want to change something:** [02](02-home-nix.md) for packages and
shell, [11](11-devshells.md) for project tools, [05](05-terminal.md) for the
terminal, [06](06-neovim.md) for the editor, [08](08-agents.md) for AI tools.
