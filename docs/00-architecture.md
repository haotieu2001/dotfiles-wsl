# 00 - How it is built

Why this repo looks the way it does. Everything in the other docs comes from the
four decisions below.

## 1. Nothing controls the system, only your home folder

A Nix setup on macOS or NixOS has two layers:

```
nix-darwin / NixOS      -> controls the machine (services, users, startup)
  home-manager          -> controls your home folder (settings, packages, shell)
```

WSL Ubuntu has nothing to put in the top layer. nix-darwin only works on macOS.
NixOS would mean throwing away Ubuntu.

So this repo uses **home-manager on its own**:

```
home-manager (on its own)  -> controls your home folder
```

What follows from that:

1. There is no `configuration.nix`. `home.nix` is the whole setup.
2. The command is `home-manager switch`, not `darwin-rebuild` or `nixos-rebuild`.
3. **No `sudo`.** home-manager only writes inside your home folder. Do not run it
   as root. `bootstrap.sh` needs `sudo` twice, for `/etc/wsl.conf` and
   `/etc/shells`, and nowhere else.
4. The flake gives you `homeConfigurations."wsl"`.
5. `apt` still works. It is your way out when nixpkgs does not have something.

This does less than NixOS, and for a laptop that is good. Nothing outside your
home folder can break, and a bad rebuild is undone by going back one step.

## 2. WSL and Windows are two different worlds

WSL is a small Linux machine running inside Windows. Anything that draws on
screen, takes your key presses, or is read by the Windows font system is a
**Windows** program. Nix runs inside Linux, so it cannot install those.

| Thing | Runs where | Installed by |
| --- | --- | --- |
| Windows Terminal | Windows | comes with Windows |
| Hack Nerd Font | Windows and Linux | `home.nix`, copied over by `install-windows-font.sh` |
| Terminal colours | Windows | `windows/`, copied once by `apply-windows-terminal-theme.sh` |
| zsh, Starship, Neovim, herdr, CLI tools | WSL | `home.nix` |
| Language versions for a project | WSL | that project's own `flake.nix` |

All the files stay in Linux, in this repo. WSL then copies what Windows needs
across by itself. There is no PowerShell step and you never need admin rights.
See [09-windows-bridge.md](09-windows-bridge.md).

## 3. Only manage files this repo owns

This rule decides what goes in and what stays out:

> If another program writes the file, or if every value in it is a matter of
> taste, this repo leaves it alone.

That one rule explains four choices that look different at first:

**The font is managed.** There is a right answer: the font must exist, and match
the version everything else was built with. Nothing else on the computer looks
after it. So we copy it again on every rebuild.

**The terminal colours are set once, not managed.** Windows Terminal writes its
own `settings.json` every time you change something in its Settings screen. If
this repo wrote that file on every rebuild, the two would fight, and whoever ran
last would win. But a **new computer** has no colours of yours to lose. So
`bootstrap.sh` sets them once and then never touches the file again.
See [05-terminal.md](05-terminal.md).

**`~/.claude` is left alone.** Claude Code writes its own `settings.json` and
`CLAUDE.md`, both by itself and by hand. If we replaced them with read-only
links, whatever was there would disappear. See [08-agents.md](08-agents.md).

**Programs that update themselves are left alone.** Claude Code keeps itself up
to date in `~/.local/bin`. If we pinned it in the Nix store, it would be frozen
at one version and would also hide the newer copy. Programs that update
themselves do not fit a system built on fixed versions.

An older version of this repo wrote Windows desktop settings to the registry:
dark mode, key repeat speed, taskbar hiding. We removed it, under the same rule.
Those are personal taste, nothing undoes them, and calling them "repeatable" was
claiming more than the repo could deliver.

## 4. Your home folder is shared, projects are not

`home.nix` installs what you want on every computer you own: git, Neovim,
ripgrep, Node, uv, direnv. It does not install a language version for one
project.

Those live in each project's own `flake.nix`. direnv loads them when you walk
into the folder, and that project's `flake.lock` writes down the versions. The
tools then travel with the code instead of living on one laptop. Two projects
can want different Python versions and nothing has to decide between them.

This is what replaces nvm, pyenv, conda and `pip install --user`. See
[11-devshells.md](11-devshells.md).

## Things that only happen on WSL

These come up because WSL is not quite a normal Linux machine:

- **systemd is off by default** in older WSL images. Nix runs a background
  service that needs it. `bootstrap.sh` notices, writes `/etc/wsl.conf`, and asks
  you to run `wsl --shutdown` once.
- **zsh has to be made the login shell.** Ubuntu starts you in bash. The `chsh`
  command refuses any shell that is not listed in `/etc/shells`, so bootstrap
  adds the Nix zsh there first.
- **Copy and paste in Neovim needs help.** WSL has no connection to the Windows
  clipboard, so copied text would vanish. `vim_config.lua` uses `clip.exe` and
  `powershell.exe` instead. See [06-neovim.md](06-neovim.md).
- **`/mnt/c` is slow.** That is the Windows disk seen from Linux, and it is much
  slower than the Linux disk. zsh jumps back to your home folder if it starts
  under `/mnt`, and `AGENTS.md` tells AI tools not to put code there.
- **The network is shaky at first.** WSL sends DNS through Windows, and that is
  briefly unavailable while things start up. So the first build tries three times
  before giving up.
