# 00 - Architecture

Why this repo is shaped the way it is. Everything in the other docs follows
from the four decisions on this page.

## 1. There is no system layer

A Nix setup on macOS or NixOS has two layers:

```
nix-darwin / NixOS      -> manages the machine (services, defaults, users)
  home-manager          -> manages $HOME (dotfiles, packages, shell)
```

WSL Ubuntu has no counterpart to the outer one. nix-darwin is macOS-only: it
works by writing macOS `defaults`, managing launchd services and driving
Homebrew, none of which exist here. NixOS would mean replacing Ubuntu entirely.

So this repo runs **home-manager standalone**:

```
home-manager (standalone)  -> manages $HOME
```

Consequences that ripple through everything else:

1. There is no `configuration.nix`. `home.nix` is the whole config.
2. The command is `home-manager switch`, not `darwin-rebuild` or `nixos-rebuild`.
3. **No `sudo`.** Standalone home-manager only writes your home directory, and
   must not be run as root. `bootstrap.sh` needs `sudo` twice, for `/etc/wsl.conf`
   and `/etc/shells`, and nowhere else.
4. The flake exposes `homeConfigurations."wsl"`.
5. `apt` still works and is not the enemy. It is the escape hatch for the rare
   thing nixpkgs cannot provide.

This is a smaller surface than NixOS, and for a laptop that is the point:
nothing outside `$HOME` can break, and a bad rebuild is undone by rolling back
a generation.

## 2. The Windows boundary

WSL is a Linux VM. Anything that draws pixels, receives keystrokes from
Windows, or is read by the Windows font renderer is a **Windows** program and
cannot be installed by Nix inside WSL.

| Component | Runs where | Installed by |
| --- | --- | --- |
| Windows Terminal | Windows | ships with Windows |
| Hack Nerd Font | Windows (and Linux) | `home.nix`, copied across by `install-windows-font.sh` |
| Terminal colour scheme | Windows | `windows/`, seeded once by `apply-windows-terminal-theme.sh` |
| zsh, Starship, Neovim, herdr, CLI tools | WSL | `home.nix` |
| Language runtimes for a project | WSL | that project's own `flake.nix` |

The config *files* all live in WSL, in this repo, and WSL pushes what Windows
needs across the boundary itself through interop. There is no PowerShell step
and nothing needs admin rights. Details in [09-windows-bridge.md](09-windows-bridge.md).

## 3. Manage only what this repo owns outright

The rule that decides what goes in and what stays out:

> If another program writes the file, or every value in it is taste rather than
> correctness, this repo does not manage it.

Applied consistently, it explains four decisions that otherwise look
inconsistent:

**The font is managed.** It has a correct answer - the glyphs must exist, at a
version matching the rest of the build - and nothing else on the machine
manages it. It is re-pushed on every rebuild.

**The terminal theme is seeded, not managed.** `settings.json` is a file
Windows Terminal itself rewrites every time you touch its Settings UI. A repo
that reasserts its values on every rebuild fights the application for ownership
and the user loses. But a *fresh machine* has no theme of yours to take away,
so `bootstrap.sh` seeds one and then never touches the file again. Seed once,
then hand off. See [05-terminal.md](05-terminal.md).

**`~/.claude` is not managed.** Claude Code edits its own `settings.json` and
`CLAUDE.md`, by the tool and by hand. Replacing them with read-only store
symlinks silently displaces whatever was there. See [08-agents.md](08-agents.md).

**Self-updating binaries are not managed.** Claude Code ships an updater that
keeps itself current in `~/.local/bin`. Pinning it in the Nix store both
freezes it and shadows the newer copy on `PATH`. Declarative packaging and
self-updating binaries are a genuinely bad match.

An earlier version of this repo shipped a `settings.ps1` that wrote Windows
desktop preferences (dark mode, key repeat rate, taskbar autohide) to the
registry. It was removed under the same rule: those are desktop appearance
preferences, nothing reverts them, and shipping imperative registry writes
under a banner of reproducibility was overclaiming.

## 4. $HOME is global, projects are not

`home.nix` installs what should exist on every machine you own: git, Neovim,
ripgrep, Node, uv, direnv. It deliberately does not install per-project
language versions.

Those live in each project's own `flake.nix`, loaded on `cd` by direnv and
pinned by that project's `flake.lock`. A toolchain then travels with the repo
instead of living on one laptop, and two projects can want different Python
versions without a version manager arbitrating.

This is the part that replaces nvm, pyenv, conda and `pip install --user`.
See [11-devshells.md](11-devshells.md).

## WSL-specific quirks worth knowing

These exist only because WSL has sharp edges a native Linux or macOS setup
never hits:

- **systemd is off by default** in older WSL images. Multi-user Nix runs a
  daemon that the Determinate installer wires up through systemd, so
  `bootstrap.sh` detects this, writes `/etc/wsl.conf`, and asks for one
  `wsl --shutdown`.
- **zsh has to be made the login shell.** Ubuntu logs you into bash, and `chsh`
  refuses any shell not listed in `/etc/shells`, so bootstrap registers the Nix
  zsh there first.
- **The Neovim clipboard needs a bridge.** There is no X selection wired to
  Windows, so yanks would vanish. `vim_config.lua` defines an explicit provider
  using `clip.exe` and `powershell.exe`. See [06-neovim.md](06-neovim.md).
- **`/mnt/c` is slow.** It is a 9p mount, drastically slower than the Linux
  filesystem. zsh bounces back to `$HOME` if it starts under `/mnt`, and
  `AGENTS.md` tells agents not to put repos there.
- **DNS is flaky during first boot.** WSL routes DNS through a host proxy that
  is briefly unreachable while systemd and the Nix daemon settle, so the first
  `home-manager switch` retries rather than failing outright.
