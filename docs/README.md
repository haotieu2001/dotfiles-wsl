# Reference

What every file does, and which one to open when you want to change something.

This is deliberately short. It covers what is specific to *this repo*. For how
Nix, home-manager, lazy.nvim or direnv work in general, search for them when you
need to; that knowledge is not repo-specific and goes stale here.

- [When you want to change something](#when-you-want-to-change-something)
- [Build files](#build-files)
- [Scripts](#scripts)
- [Linked config](#linked-config)
- [The terminal](#the-terminal)
- [Per-project tools](#per-project-tools)
- [Decisions that will surprise you](#decisions-that-will-surprise-you)
- [When something breaks](#when-something-breaks)

## When you want to change something

| You want to | Open | Then |
| --- | --- | --- |
| Add or remove a command line tool | `home.nix`, `home.packages` | `./rebuild.sh` |
| Add a shell alias or shortcut | `home.nix`, `programs.zsh` | `./rebuild.sh` |
| Change the prompt | `home.nix`, `programs.starship` | `./rebuild.sh` |
| Move to a newer nixpkgs | `nix flake update` | `./rebuild.sh` |
| Change a Neovim setting | `home/.config/nvim/lua/vim_config.lua` | nothing, it is linked |
| Add a Neovim plugin | new file in `home/.config/nvim/lua/plugins/` | nothing |
| Change a Neovim key | `home/.config/nvim/lua/keys.lua` | nothing |
| Change herdr keys | `home/.config/herdr/config.toml` | nothing |
| Change how AI tools behave | `home/AGENTS.md` | nothing |
| Change terminal colours **now** | Windows Terminal's own Settings | nothing |
| Save terminal colours for the **next** machine | `windows/*.json` | `./scripts/apply-windows-terminal-theme.sh --force` |
| Give one project its own toolchain | that project, not this repo | see [Per-project tools](#per-project-tools) |
| Find what is installed outside Nix | - | `./scripts/check-drift.sh` |

The rule behind the "then" column: **anything under `home/` is symlinked into
place, so edits work immediately.** Everything else is built by Nix and needs
`./rebuild.sh`.

## Build files

| File | What it does |
| --- | --- |
| `flake.nix` | The entry point. Pins nixpkgs and home-manager, sets `user = `, and exposes `homeConfigurations."wsl"` plus the two project templates. |
| `flake.lock` | The exact commit of every input. This file is what makes a new machine identical rather than merely similar. Commit it. |
| `home.nix` | The whole user environment: package list, zsh, Starship, direnv, and the symlinks into `home/`. The file you edit most. |
| `modules/herdr.nix` | Packages herdr, which is not in nixpkgs, from its upstream release binary pinned by version and hash. Copy this file as a pattern when you need another tool that nixpkgs does not carry. |

`user = ` in `flake.nix` must match your Linux username. `bootstrap.sh` step 4
offers to set it for you.

## Scripts

| Script | When it runs | What it does |
| --- | --- | --- |
| `bootstrap.sh` | once, on a new machine | Steps 0-8: checks WSL, turns on systemd, installs Determinate Nix, links `~/.dotfiles`, sets your username, first build, makes zsh your login shell, installs the font, seeds terminal colours. |
| `rebuild.sh` | every time you change a build file | `home-manager switch`, then pushes the font to Windows. Safe to run repeatedly. |
| `scripts/install-windows-font.sh` | from `bootstrap.sh` and every `rebuild.sh` | Copies Hack Nerd Font from the Nix store into the Windows font folder, so the font version is pinned by `flake.lock` like everything else. |
| `scripts/apply-windows-terminal-theme.sh` | from `bootstrap.sh` **only**, once | Merges `windows/*.json` into Windows Terminal's `settings.json`. Backs the file up first, and refuses to overwrite a scheme that is already there unless you pass `--force`. |
| `scripts/check-drift.sh` | whenever you want | Reports software installed outside Nix, and tools where a non-Nix copy is winning on `PATH`. Read-only. Exit 1 means real drift. |

`bootstrap.sh` is safe to re-run. If step 1 asks you to run `wsl --shutdown`, do
that from PowerShell and run it again.

## Linked config

Everything under `home/` is symlinked into your home folder by `home.nix`, so
the file in this repo *is* the file the program reads. Edit and it takes effect.

| File | What it does |
| --- | --- |
| `home/AGENTS.md` | Shared instructions read by Claude Code, Codex and opencode. Linked to `~/.codex/AGENTS.md` and `~/.config/opencode/AGENTS.md`. |
| `home/.config/herdr/config.toml` | herdr keybindings. Prefix is `ctrl+b`, then `c` new tab, `%` and `"` split, `hjkl` move between panes, `w` workspace picker, `y` copy mode. |
| `home/.config/nvim/init.lua` | Loads the three modules below, in order. |
| `home/.config/nvim/lua/vim_config.lua` | Editor settings, and the WSL clipboard bridge. |
| `home/.config/nvim/lua/plugin.lua` | Bootstraps lazy.nvim and tells it to load every file in `plugins/`. |
| `home/.config/nvim/lua/keys.lua` | Key bindings. `Esc` saves, `ctrl+a` selects all, and `p` over a selection keeps your clipboard. |
| `home/.config/nvim/lua/plugins/*.lua` | One file per group of plugins: `colorscheme`, `git`, `navigation`, `ui`. Drop in a new file to add a plugin. |

The clipboard bridge in `vim_config.lua` is the one part worth knowing about.
`clipboard = 'unnamedplus'` works on macOS because Neovim finds `pbcopy`. A WSL
VM has no X selection connected to Windows, so Neovim would yank into nothing.
The fix routes copy through `clip.exe` and paste through `powershell.exe`,
stripping the `\r` Windows adds. Without that strip every pasted line ends
in `^M`.

## The terminal

| File | What it is |
| --- | --- |
| `windows/blackpanther.json` | The colour scheme. |
| `windows/profile-defaults.json` | Font, size, opacity, padding, cursor, and the background image reference. |
| `windows/blackpanther.jpg` | The background image. |

These are applied **once**, by `bootstrap.sh` step 8. `rebuild.sh` never writes
Windows Terminal's settings.

That is on purpose. `settings.json` is a file you also edit through Windows
Terminal's own Settings screen, and every value in it is taste. A repo that
rewrote it on every rebuild would fight you for control of your own terminal.
Seeding it once gives a new machine your look without ever undoing a change you
made yourself.

So: change colours **now** in the Settings screen. Change what the **next**
machine gets by editing `windows/*.json`. To pull your edited files onto this
machine as well, run the script with `--force`.

Nothing here requires Windows Terminal. Any terminal with truecolor and Hack
Nerd Font works.

## Per-project tools

`home.nix` installs what you want on every machine. A version of Python or Node
that only one project needs belongs in that project:

```bash
cd ~/my-api
nix flake init -t ~/.dotfiles#python    # or #node
direnv allow
```

Now the tools appear when you walk into the folder and disappear when you leave.
The versions live in that project's own `flake.lock`, so they travel with the
code instead of living on one laptop. This is what replaces nvm, pyenv, conda
and `pip install --user`.

| File | What it does |
| --- | --- |
| `templates/python/flake.nix` | Python 3.12, uv and ruff. Nix pins the interpreter, uv pins the packages in `uv.lock`. |
| `templates/node/flake.nix` | Node 24 and pnpm. |
| `templates/*/.envrc` | One line, `use flake`. This is what direnv reads. |

Each template pins nixpkgs independently of this repo, so updating your dotfiles
does not move a project's toolchain, and vice versa.

## Decisions that will surprise you

Short list of things that look like bugs and are not.

**`~/.dotfiles` is a symlink, and every link goes through it.** That is why you
can move or rename the repo folder and nothing breaks. Both scripts recreate it.

**`stateVersion` is not a version to keep current.** It locks in defaults that
home-manager might change later. Set once, then never touch it.

**Claude Code is deliberately not installed by Nix.** It updates itself, and the
Nix store is read-only. Pinning it would freeze it and shadow the newer copy.
It lives in `~/.local/bin` on purpose.

**`~/.claude` is deliberately not managed.** Claude Code edits its own
`settings.json`, so home-manager replacing it with a store symlink would
silently displace whatever was there. Only symlink files this repo owns
outright.

**`direnv` is not in `home.packages`.** The `programs.direnv` block installs it
*and* wires it into zsh. Listing it in both places is a redundant second path to
the same package.

**`git` is in `home.packages` even though you need git to clone this repo.** The
first git comes from apt; this one is pinned and wins once you have installed.

**Neovim plugins are not pinned.** lazy.nvim manages them, and
`lazy-lock.json` is gitignored. Delete that line from `.gitignore` if you want
them locked.

**Windows settings outside the terminal are not managed.** An earlier version of
this repo wrote to the Windows registry. It was removed for claiming more than
it could deliver.

## When something breaks

| Symptom | Cause and fix |
| --- | --- |
| `bootstrap.sh` says to run `wsl --shutdown` | Normal. systemd needs a restart. Run it in PowerShell, reopen Ubuntu, run `./bootstrap.sh` again. |
| `nix: command not found` after installing | Nix is only added to *new* shells. Open one, or `. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh`. |
| `Could not resolve host` during the first build | Almost always temporary; WSL's network is briefly unavailable while Nix and systemd start. Run `./bootstrap.sh` again, it resumes. |
| `Existing file ... would be clobbered` | You ran home-manager without `-b backup`. Use `./rebuild.sh`. |
| Still in bash after installing | `chsh` failed, which is common under WSL. Check with `getent passwd "$USER" \| cut -d: -f7`. |
| Prompt shows boxes instead of icons | Windows has not picked up the font. Run `./scripts/install-windows-font.sh`, then sign out of Windows and back in. |
| A tool is a different version from `home.nix` | Something non-Nix is earlier on `PATH`. Run `./scripts/check-drift.sh`. |
| Added a package, command not found | Profile is stale. `./rebuild.sh`, then open a new shell. |
| Edited `home/` and nothing changed | Those are linked, so it should be instant. If not, the `~/.dotfiles` link is wrong: `cd` to the repo and run `./rebuild.sh`. |
| Every build is slow | The repo is on the Windows disk. `pwd -P` must start with `/home`, not `/mnt`. |
| A rebuild made things worse | `home-manager generations`, then run the `activate` script of an older one. |

Full uninstall:

```bash
nix run home-manager/release-26.05 -- uninstall
/nix/nix-installer uninstall
```
