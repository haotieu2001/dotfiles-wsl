# Docs

Line-by-line explanation of every file in this repo.

Start with [00 - Architecture](00-architecture.md). It covers the four
decisions - no system layer, the Windows boundary, managing only what this repo
owns, and keeping projects out of `$HOME` - that everything else follows from.

| Doc | Covers |
| --- | --- |
| [00 - Architecture](00-architecture.md) | The four decisions the repo is built on |
| [01 - flake.nix](01-flake-nix.md) | Inputs, pinning, the `user` line, `homeConfigurations`, templates |
| [02 - home.nix](02-home-nix.md) | Packages, zsh, Starship, direnv, and `mkOutOfStoreSymlink` |
| [03 - modules/herdr.nix](03-modules-herdr-nix.md) | Packaging a pinned upstream binary in Nix |
| [04 - bootstrap.sh and rebuild.sh](04-bootstrap-and-rebuild.md) | Both scripts, step by step |
| [05 - The terminal](05-terminal.md) | Seeding the theme, and why it is seeded rather than managed |
| [06 - Neovim](06-neovim.md) | Every Lua file, including the WSL clipboard bridge |
| [07 - herdr](07-herdr.md) | Keybindings and running agents in panes |
| [08 - Agents](08-agents.md) | `AGENTS.md` fan-out, and what this repo refuses to manage |
| [09 - The Windows bridge](09-windows-bridge.md) | The two scripts that cross the boundary |
| [10 - Troubleshooting](10-troubleshooting.md) | WSL-specific failure modes |
| [11 - Devshells](11-devshells.md) | Per-project toolchains with flakes and direnv |

## Reading order

**Setting up:** the root [README](../README.md), then
[04](04-bootstrap-and-rebuild.md), then [09](09-windows-bridge.md).

**Understanding it:** [00](00-architecture.md), [01](01-flake-nix.md),
[02](02-home-nix.md).

**Customizing:** [02](02-home-nix.md) for packages and shell,
[11](11-devshells.md) for project toolchains, [05](05-terminal.md) for the
terminal, [06](06-neovim.md) for the editor, [08](08-agents.md) for agent
behavior.
