# dotfiles-wsl

My whole WSL2 Ubuntu setup, written down in files. One command puts it on a new
computer.

Get a new Windows laptop, clone this repo, run `./bootstrap.sh`, and you get the
same packages, the same shell, the same editor and the same terminal colours you
had before.

## What you get

- Packages installed by Nix, so everyone gets the same versions
- zsh, with command suggestions and colours
- The Starship prompt
- Neovim, set up and ready
- herdr, a tool for running many terminals in one window
- One `AGENTS.md` file that every AI coding tool reads
- Hack Nerd Font, installed on the Windows side
- Your terminal colours, set up on the first install

## Contents

- [How it works](#how-it-works)
- [Before you start](#before-you-start)
- [Install](#install)
- [Everyday use](#everyday-use)
- [Tools for one project](#tools-for-one-project)
- [Making changes](#making-changes)
- [What is in this repo](#what-is-in-this-repo)
- [What this repo can and cannot rebuild](#what-this-repo-can-and-cannot-rebuild)
- [Docs](#docs)

## How it works

Three ideas explain the whole repo.

**Anything that can live in WSL, lives in WSL.** Packages, shell, editor and
settings are all managed by Nix. The file `flake.lock` writes down the exact
version of everything. Delete your Linux install, clone this repo, run
`./bootstrap.sh`, and you are back where you were.

**Your home folder is shared, your projects are not.** This repo installs the
tools you want on *every* computer. But one project may need Python 3.12 and
another may need Python 3.10. Those go in the project itself, not here. See
[Tools for one project](#tools-for-one-project).

**The terminal is a Windows program, so we set it up once and then leave it
alone.** Windows Terminal draws your window. Nix runs inside Linux and cannot
reach it. Two things cross over when you install: the font, and the colours.
After that the terminal is yours to change.

<p align="center">
  <img src="docs/assets/architecture.svg" width="900"
       alt="One repo drives two sides. home-manager switch builds everything inside WSL2 Ubuntu: CLI tools, herdr, live-symlinked config, and per-project devshells loaded by direnv. bootstrap.sh and rebuild.sh push across the WSL/Windows boundary: the Hack Nerd Font on every rebuild, and the Windows Terminal colour scheme once at install. Windows Terminal attaches back to herdr.">
</p>

Files under `home/` are linked, not copied. So when you edit one, the change
works right away. You only need to rebuild when you add or remove a package.

## Before you start

You need:

- Windows 10 22H2 or Windows 11, with **Windows Terminal** (already installed on
  Windows 11)
- WSL2 with Ubuntu. Install it with `wsl --install -d Ubuntu`
- `git` inside WSL: `sudo apt install -y git`. This is the only thing you install
  with apt.

Check that you have WSL**2**, not WSL1. WSL1 cannot run Nix:

```powershell
wsl -l -v      # the VERSION column must say 2
```

## Install

```bash
git clone https://github.com/<you>/dotfiles-wsl.git ~/dotfiles-wsl
cd ~/dotfiles-wsl
./bootstrap.sh
```

That is the whole install. You do not need to run anything on the Windows side.

| Step | What it does |
| --- | --- |
| 0 | Checks that you are in WSL |
| 1 | Turns on systemd, which Nix needs |
| 2 | Installs [Determinate Nix](https://install.determinate.systems/) |
| 3 | Links the repo to `~/.dotfiles` |
| 4 | Offers to change the `user = ` line in `flake.nix` to your username |
| 5 | Builds and installs everything for the first time |
| 6 | Makes zsh your login shell |
| 7 | Installs Hack Nerd Font on Windows |
| 8 | Sets your terminal colours, one time only |

> If step 1 asks you to run `wsl --shutdown`, do it from **PowerShell**. Then
> open Ubuntu again and run `./bootstrap.sh` again. Turning on systemd needs a
> restart.

The first build downloads a lot of files. This is normal and happens only once.

When it finishes, close and reopen Windows Terminal. If you see boxes instead of
icons, sign out of Windows and back in. Windows needs this to notice a new font.

## Everyday use

```bash
./rebuild.sh       # apply any change to packages, shell or editor
```

You do **not** need to rebuild after editing files in `home/` (Neovim, herdr,
`AGENTS.md`). Those are linked, so changes work right away. Rebuild only when you
change which packages Nix installs.

`rebuild.sh` does not touch your terminal colours. See
[the terminal doc](docs/05-terminal.md) to learn why.

To start the terminal multiplexer, run `herdr`. The keys are the same as tmux:
`ctrl+b` first, then `c` for a new tab, `%` or `"` to split the window.

## Tools for one project

`home.nix` installs tools you want everywhere: Node 24, uv, git, ripgrep,
Neovim. It does not install a version of Python or Node for one project. That
goes in the project:

```bash
cd ~/my-api
nix flake init -t ~/.dotfiles#python    # or #node
direnv allow
```

Now walk into the folder and the tools appear:

```
$ cd ~/my-api
direnv: loading ~/my-api/.envrc
$ python --version
Python 3.12.13

$ cd ..
direnv: unloading
$ python --version
Python 3.14.4        # Ubuntu's own Python again
```

The versions are written down in the project's own `flake.lock`. So they travel
with the code, instead of living on one laptop.

This replaces nvm, pyenv, conda and `pip install --user`. Read more in
[docs/11-devshells.md](docs/11-devshells.md).

## Making changes

**Add a command line tool.** Find it on
[search.nixos.org](https://search.nixos.org/packages), add it to `home.packages`
in `home.nix`, then run `./rebuild.sh`. If only one project needs it, put it in
that project's flake instead.

**Add a shell shortcut.** Add it to `programs.zsh.shellAliases` in `home.nix`,
then rebuild.

**Change terminal colours, see-through level or padding.** Use Windows
Terminal's own Settings screen. This repo sets the colours once when you install
and never writes that file again. If you want to save new colours for future
computers, edit the files in `windows/` and run
`./scripts/apply-windows-terminal-theme.sh --force`.

**Add a Neovim plugin.** Put a file in `home/.config/nvim/lua/plugins/`.
lazy.nvim loads every file in that folder. No rebuild needed.

**Change how AI tools behave.** Edit `home/AGENTS.md`. Claude Code, Codex and
opencode all read it. No rebuild needed.

**Use a different terminal.** Nothing here needs Windows Terminal. Install
whatever you like. You only need Hack Nerd Font and truecolor support. You can
also add `wezterm` or `kitty` to `home.packages` and run it as a Linux window
through WSLg. That is fully repeatable, but text looks blurrier and typing feels
slower. See [docs/05-terminal.md](docs/05-terminal.md).

## What is in this repo

```
dotfiles-wsl/
├── flake.nix                       # versions, and the one `user =` line
├── home.nix                        # packages, zsh, starship, direnv, links
├── modules/herdr.nix               # herdr, pinned to one version
├── bootstrap.sh                    # first-time setup
├── rebuild.sh                      # the everyday command
├── scripts/
│   ├── install-windows-font.sh     # font to Windows, every rebuild
│   └── apply-windows-terminal-theme.sh   # colours to Windows, install only
├── windows/                        # what gets copied to the Windows side
│   ├── blackpanther.json           # the colour scheme
│   ├── profile-defaults.json       # font, see-through level, padding, cursor
│   └── blackpanther.jpg            # background picture
├── templates/                      # `nix flake init -t ~/.dotfiles#python`
│   ├── python/
│   └── node/
├── home/                           # linked into your home folder
│   ├── AGENTS.md                   # shared notes for every AI tool
│   └── .config/
│       ├── herdr/config.toml
│       └── nvim/
│           ├── init.lua
│           └── lua/
│               ├── vim_config.lua  # settings + the Windows copy-paste fix
│               ├── plugin.lua      # lazy.nvim setup
│               ├── keys.lua
│               └── plugins/        # one file per plugin
└── docs/                           # what every file does, line by line
```

## What this repo can and cannot rebuild

This matters, because rebuilding is the whole point.

**Always the same**, written down in Nix and locked by `flake.lock`: every
command line tool, Node, uv, direnv, Neovim, zsh and its plugins, Starship,
herdr, the font files, and every link into your home folder.

**Always the same for each project**, locked by that project's own
`flake.lock`: language versions and project tools, loaded by direnv.

**Set once when you install, then yours**: terminal colours, font size,
see-through level and background picture. A new computer gets your look
automatically. After that, this repo never writes that file again, so nothing
undoes a change you make yourself.

**Not managed at all**: Windows Terminal itself, and Windows desktop settings.
An older version of this repo wrote Windows settings to the registry. We removed
it, because it claimed more than it could deliver.

**On purpose, not locked**: Neovim plugins, managed by lazy.nvim. Commit
`home/.config/nvim/lazy-lock.json` if you want to lock them. AI tools that update
themselves, like Claude Code, are also left alone. See
[docs/08-agents.md](docs/08-agents.md).

## Docs

| Doc | What it covers |
| --- | --- |
| [00 - How it is built](docs/00-architecture.md) | The four decisions behind the repo |
| [01 - flake.nix](docs/01-flake-nix.md) | Versions, locking, and templates |
| [02 - home.nix](docs/02-home-nix.md) | Packages, zsh, Starship, direnv, links |
| [03 - modules/herdr.nix](docs/03-modules-herdr-nix.md) | How to package a downloaded program |
| [04 - The two scripts](docs/04-bootstrap-and-rebuild.md) | `bootstrap.sh` and `rebuild.sh`, step by step |
| [05 - The terminal](docs/05-terminal.md) | Setting colours once, and why only once |
| [06 - Neovim](docs/06-neovim.md) | Every Lua file, and the copy-paste fix |
| [07 - herdr](docs/07-herdr.md) | Keys, and running AI tools side by side |
| [08 - AI tools](docs/08-agents.md) | `AGENTS.md`, and what this repo will not touch |
| [09 - Talking to Windows](docs/09-windows-bridge.md) | The two scripts that cross over |
| [10 - When things break](docs/10-troubleshooting.md) | Problems you may hit on WSL |
| [11 - Tools per project](docs/11-devshells.md) | flakes and direnv |

## Credit

Based on a macOS nix-darwin setup by
[kunchenguid](https://github.com/kunchenguid/dotfiles). Not an official version.

## License

MIT-0.
