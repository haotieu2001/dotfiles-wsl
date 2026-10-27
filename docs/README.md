# Reference

What every file does, and which one to open when you want to change something.

This is deliberately short. It covers what is specific to *this repo*. For how
apt, uv, lazy.nvim or direnv work in general, search for them when you need to;
that knowledge is not repo-specific and goes stale here.

- [When you want to change something](#when-you-want-to-change-something)
- [Install files](#install-files)
- [Scripts](#scripts)
- [Linked config](#linked-config)
- [The terminal](#the-terminal)
- [Per-project tools](#per-project-tools)
- [Decisions that will surprise you](#decisions-that-will-surprise-you)
- [When something breaks](#when-something-breaks)

## When you want to change something

| You want to | Open | Then |
| --- | --- | --- |
| Add or remove an apt package | `packages/apt.txt` | `./bootstrap.sh` |
| Add a tool apt does not have | `packages/pinned.sh` + step 3 of `bootstrap.sh` | `./bootstrap.sh` |
| Upgrade herdr, lua-language-server or the font | version + SHA-256 in `packages/pinned.sh` | `./bootstrap.sh` |
| Upgrade everything else | - | `./update.sh` |
| Add a shell alias or shortcut | `home/.zshrc` | open a new shell |
| Change an environment variable or PATH | `home/.zshenv` | open a new shell |
| Change the prompt | `home/.config/starship.toml` | nothing, it is linked |
| Change a Neovim setting | `home/.config/nvim/lua/vim_config.lua` | nothing, it is linked |
| Add a Neovim plugin | new file in `home/.config/nvim/lua/plugins/` | nothing |
| Change a Neovim key | `home/.config/nvim/lua/keys.lua` | nothing |
| Change herdr keys | `home/.config/herdr/config.toml` | nothing |
| Change how AI tools behave | `home/AGENTS.md` | nothing |
| Change terminal colours **now** | Windows Terminal's own Settings | nothing |
| Save terminal colours for the **next** machine | `windows/*.json` | `./scripts/apply-windows-terminal-theme.sh --force` |
| Give one project its own Python | that project, with uv | see [Per-project tools](#per-project-tools) |
| Check this machine matches the repo | - | `./scripts/check-drift.sh` |

The rule behind the "then" column: **anything under `home/` is symlinked into
place, so edits work immediately.** Packages are installed by `bootstrap.sh`, so
a package change means running it again.

## Install files

| File | What it does |
| --- | --- |
| `packages/apt.txt` | Every apt package, one per line. `gh`, `terraform` and `nodejs` resolve to their vendors' repos, which `bootstrap.sh` adds in step 1. |
| `packages/pinned.sh` | Downloads that are not in apt: herdr, lua-language-server and Hack Nerd Font, each with a version, URL and SHA-256. Also the npm and uv global tool lists. |

To get a new digest for a GitHub release asset:

```bash
gh api repos/OWNER/REPO/releases/tags/TAG --jq '.assets[] | .name + " " + .digest'
```

## Scripts

| Script | When it runs | What it does |
| --- | --- | --- |
| `bootstrap.sh` | once on a new machine, and after any change in `packages/` | Steps 0-8: checks WSL, apt (with vendor repos), Databricks CLI and uv, language servers and pinned downloads, links, cleans up old Nix lines, login shell, font, terminal colours. Every step checks before acting, so re-running is safe. |
| `update.sh` | whenever you want newer versions | `apt upgrade`, re-installs the Databricks CLI, `uv self update`, `uv tool upgrade --all`, `npm update -g`, then re-runs `bootstrap.sh` quietly. |
| `scripts/link.sh` | from `bootstrap.sh` step 4 | Links each file under `home/` into `$HOME` through `~/.dotfiles`. Backs up a real file before replacing it, and removes old home-manager links into `/nix/store`. |
| `scripts/install-windows-font.sh` | from `bootstrap.sh` | Copies Hack Nerd Font from `~/.local/share/fonts/HackNerdFont` into the Windows per-user font folder and registers it. |
| `scripts/apply-windows-terminal-theme.sh` | from `bootstrap.sh`, seeds once | Merges `windows/*.json` into Windows Terminal's `settings.json`. Backs the file up first, and refuses to overwrite a scheme that is already there unless you pass `--force`. Skip it with `DOTFILES_SKIP_THEME=1 ./bootstrap.sh`. |
| `scripts/check-drift.sh` | whenever you want | Checks every declared tool is installed and comes from where it should, lists anything undeclared in `~/.local/bin`, and reports Nix leftovers. Read-only. Exit 1 means something needs fixing. |

## Linked config

Everything under `home/` is symlinked into your home folder by `scripts/link.sh`,
so the file in this repo *is* the file the program reads. Edit and it takes effect.

| File | What it does |
| --- | --- |
| `home/.zshenv` | Read by every zsh: `EDITOR`, `~/.local/bin` at the front of `PATH`, rustup's env file. |
| `home/.zshrc` | Interactive zsh: completion, history, the apt zsh plugins, `winhome` and `open`, starship, direnv, aliases. |
| `home/.config/starship.toml` | The prompt. |
| `home/AGENTS.md` | Shared instructions read by Claude Code, Codex and opencode. Linked to `~/.codex/AGENTS.md` and `~/.config/opencode/AGENTS.md`. |
| `home/.config/herdr/config.toml` | herdr keybindings. Prefix is `ctrl+b`, then `c` new tab, `%` and `"` split, `hjkl` move between panes, `w` workspace picker, `y` copy mode. |
| `home/.config/nvim/init.lua` | Loads the three modules below, in order. |
| `home/.config/nvim/lua/vim_config.lua` | Editor settings, and the WSL clipboard bridge. |
| `home/.config/nvim/lua/plugin.lua` | Bootstraps lazy.nvim and tells it to load every file in `plugins/`. |
| `home/.config/nvim/lua/keys.lua` | Key bindings. `Esc` saves, `ctrl+a` selects all, and `p` over a selection keeps your clipboard. |
| `home/.config/nvim/lua/plugins/*.lua` | One file per group of plugins: `colorscheme`, `git`, `lsp`, `navigation`, `ui`. Drop in a new file to add a plugin. |
| `home/.config/nvim/lua/plugins/lsp.lua` | Enables the language servers `bootstrap.sh` installs. No `setup()` calls: Neovim 0.11+ reads nvim-lspconfig's per-server config itself via `vim.lsp.enable`. |

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

These are applied **once**, by `bootstrap.sh` step 8. Later runs, including the
one inside `update.sh`, find the scheme already there and change nothing.

That is on purpose. `settings.json` is a file you also edit through Windows
Terminal's own Settings screen, and every value in it is taste. A repo that
rewrote it on every run would fight you for control of your own terminal.
Seeding it once gives a new machine your look without ever undoing a change you
made yourself.

So: change colours **now** in the Settings screen. Change what the **next**
machine gets by editing `windows/*.json`. To pull your edited files onto this
machine as well, run the script with `--force`.

### If you cloned this and want your own theme

The one-time seed still overwrites `colorScheme`, `font`, `opacity`, `padding`,
`cursorShape` and the background image. Everything else in `profiles.defaults`
survives, your own schemes stay in `.schemes`, and the old file is backed up as
`settings.json.pre-dotfiles-wsl.*`. Three ways out:

- **Keep your look:** `DOTFILES_SKIP_THEME=1 ./bootstrap.sh`. You still get the
  font, which is the only part the terminal genuinely needs from this repo.
- **Undo it after the fact:** pick your scheme again in the Settings screen. The
  seed-once guard then leaves you alone forever, including on re-runs.
- **Ship yours instead:** replace `windows/blackpanther.{json,jpg}` and point
  `SCHEME_FILE` / `IMAGE_FILE` at the top of the script at them.

The scheme's `name` and `colorScheme` in `profile-defaults.json` must agree.
The script checks and refuses to run otherwise: Windows Terminal ignores a
`colorScheme` it cannot resolve, so a mismatch shows up as "the theme did
nothing" rather than as an error.

Nothing here requires Windows Terminal. Any terminal with truecolor and Hack
Nerd Font works.

## Per-project tools

This repo installs what you want on every machine. A Python version or package
set that only one project needs belongs in that project, managed by uv:

```bash
cd ~/my-api
uv init --python 3.12     # pyproject.toml + .python-version
uv add ruff --dev         # dependencies pinned in uv.lock
uv run pytest             # runs with that project's Python and .venv
```

uv downloads the Python version the project asks for, so nothing extra is
installed globally. `.python-version`, `pyproject.toml` and `uv.lock` are
committed with the code; `uv sync` recreates the environment on another laptop.

Node has no per-project version switching here: every project gets the global
Node 24. The Nix templates (`templates/python`, `templates/node`) that used to
provide per-project toolchains were removed with Nix.

direnv is still installed and hooked into zsh, for per-project environment
variables: an `.envrc` with `dotenv` or `source .venv/bin/activate`, then
`direnv allow`.

## Decisions that will surprise you

Short list of things that look like bugs and are not.

**`~/.dotfiles` is a symlink, and every link goes through it.** That is why you
can move or rename the repo folder and nothing breaks: re-run `./bootstrap.sh`
and it points `~/.dotfiles` at the new place.

**`~/.local/bin` comes first on `PATH`.** It holds what this repo installs
outside apt (uv, herdr, the language servers) plus self-updating tools (Claude
Code, the AWS CLI). Putting it first means a newer copy there beats an older apt
one. `check-drift.sh` reports anything in it the repo does not declare.

**Most versions are not locked.** apt and the vendor repos give you whatever is
current the day you install. That is the trade made by leaving Nix. Only the
three GitHub downloads in `packages/pinned.sh` are byte-for-byte identical on
every machine. Run `./update.sh` on both laptops to bring them level.

**Claude Code is deliberately not installed here.** It updates itself into
`~/.local/bin`; managing it from this repo would fight that.

**`~/.claude` is deliberately not managed.** Claude Code edits its own
`settings.json`, so replacing it with a symlink would silently displace whatever
was there. Only link files this repo owns outright.

**Language servers are not installed by mason.** mason downloads binaries into
`~/.local/share/nvim`, which are absent on a new machine and invisible to this
repo. `bootstrap.sh` installs them instead, and `check-drift.sh` checks they are
there. A server that is enabled in `lsp.lua` but not installed is silently
skipped.

**`fd` is a link to `fdfind`.** Debian renamed the binary to avoid a clash with
another package; `bootstrap.sh` links `~/.local/bin/fd` so the usual name works.

**`lua-language-server` in `~/.local/bin` is a two-line wrapper, not a link.** The
server finds its runtime files relative to the path it was started from.

**Neovim plugins are not pinned.** lazy.nvim manages them, and
`lazy-lock.json` is gitignored. Delete that line from `.gitignore` if you want
them locked.

**The seed-once guard looks up the scheme by the name in `windows/*.json`,
not a hardcoded one.** It used to hardcode `blackpanther` while the merge read
the name from the file. Any fork that renamed its scheme therefore never
tripped the guard and had the theme reasserted on every `bootstrap.sh` run -
the exact behaviour the script exists to prevent.

**Windows settings outside the terminal are not managed.** An earlier version of
this repo wrote to the Windows registry. It was removed for claiming more than
it could deliver.

## When something breaks

| Symptom | Cause and fix |
| --- | --- |
| `bootstrap.sh` stops at a `sudo` prompt | Normal: apt needs your Linux password. |
| `chsh: PAM: Authentication failure` | `chsh` wants your Linux password, and fails under some WSL setups. `bootstrap.sh` then launches zsh from `~/.bashrc` instead, which works the same. |
| Still in bash after installing | Open a **new** terminal. Check with `getent passwd "$USER" \| cut -d: -f7`. |
| Prompt shows boxes instead of icons | Windows has not picked up the font. Run `./scripts/install-windows-font.sh`, then sign out of Windows and back in. |
| `checksum mismatch` during step 3 | The download changed or was cut short. Re-run; if it persists, the release asset was replaced and the digest in `packages/pinned.sh` needs checking. |
| A tool is a different version than expected | Something earlier on `PATH` is winning. Run `./scripts/check-drift.sh`. |
| Added a package, command not found | Re-run `./bootstrap.sh`, then open a new shell. |
| Edited `home/` and nothing changed | Those are linked, so it should be instant (zsh: new shell). If not, the `~/.dotfiles` link is wrong: run `./bootstrap.sh` from the repo. |
| Everything is slow | The repo is on the Windows disk. `pwd -P` must start with `/home`, not `/mnt`. |
